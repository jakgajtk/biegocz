import Foundation

/// The live state of a run or ride: pause / auto-pause, distance, moving
/// time and the route. Pure and `Codable`, so it can be persisted for crash
/// recovery (the route itself is stored separately, see `segments`).
struct CardioEngine: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case running, paused, autoPaused
    }

    let activityType: ActivityType
    let startDate: Date
    var autoPauseEnabled: Bool
    /// Seconds without movement before auto-pause kicks in.
    var autoPauseDelay: TimeInterval = 10

    private(set) var state: State = .running
    private(set) var distance: Double = 0
    private var accumulatedMovingTime: TimeInterval = 0
    /// Start of the current moving stretch; `nil` while paused.
    private var movingSince: Date?
    private var lastMovementAt: Date?
    private(set) var filter: LocationFilter
    private(set) var smoother: SpeedSmoother
    /// Time of the last persisted snapshot, used when recovering after a crash.
    var savedAt: Date?

    /// The route, split at pauses. Not part of the `Codable` state.
    private(set) var segments: [[RoutePoint]] = [[]]

    private enum CodingKeys: String, CodingKey {
        case activityType, startDate, autoPauseEnabled, autoPauseDelay, state, distance
        case accumulatedMovingTime, movingSince, lastMovementAt, filter, smoother, savedAt
    }

    init(activityType: ActivityType, startDate: Date, autoPauseEnabled: Bool = false) {
        let config = LocationFilterConfig.forActivity(activityType)
        self.activityType = activityType
        self.startDate = startDate
        self.autoPauseEnabled = autoPauseEnabled
        self.filter = LocationFilter(config: config)
        self.smoother = SpeedSmoother(movingSpeed: config.movingSpeed)
        self.movingSince = startDate
        self.lastMovementAt = startDate
    }

    // MARK: Readings

    func elapsedTime(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(startDate))
    }

    func movingTime(at now: Date) -> TimeInterval {
        accumulatedMovingTime + (movingSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    /// Smoothed current speed in m/s; `nil` when paused or not moving.
    func currentSpeed(at now: Date) -> Double? {
        state == .running ? smoother.currentSpeed(at: now) : nil
    }

    func averageSpeed(at now: Date) -> Double? {
        let time = movingTime(at: now)
        guard time > 0, distance > 0 else { return nil }
        return distance / time
    }

    var routePointCount: Int { segments.reduce(0) { $0 + $1.count } }

    // MARK: Events

    mutating func pause(at now: Date) {
        guard state != .paused else { return }
        stopMovingClock(at: now)
        state = .paused
        filter.reset()
        smoother.reset()
    }

    mutating func resume(at now: Date) {
        guard state == .paused else { return }
        state = .running
        movingSince = now
        lastMovementAt = now
        startNewSegment()
    }

    /// Feeds one raw fix. Ignored while paused manually.
    @discardableResult
    mutating func ingest(_ point: RoutePoint, receivedAt now: Date) -> FilterDecision? {
        guard state != .paused else { return nil }
        let previous = filter.lastAccepted
        let decision = filter.process(point, receivedAt: now)

        switch decision {
        case .accepted(var stepDistance):
            if state == .autoPaused {
                // Drift while standing still isn't movement: only resume when the
                // step since the last accepted point implies moving speed.
                let interval = previous.map { point.timestamp.timeIntervalSince($0.timestamp) } ?? 0
                guard interval > 0, stepDistance / interval >= filter.config.movingSpeed else {
                    return decision
                }
                state = .running
                movingSince = point.timestamp
                // The new stretch starts here; the few meters bridging the stop
                // aren't counted, so the distance always equals the segments' length.
                stepDistance = 0
                startNewSegment()
            } else if stepDistance == 0, previous != nil {
                // The filter re-anchored after a bad fix: don't draw or count the jump.
                startNewSegment()
            }
            distance += stepDistance
            segments[segments.count - 1].append(point)
            lastMovementAt = point.timestamp
            smoother.add(time: point.timestamp, totalDistance: distance)
        case .stationary:
            if state == .running {
                smoother.add(time: point.timestamp, totalDistance: distance)
            }
        case .rejected:
            break
        }
        return decision
    }

    /// Called about once a second; handles auto-pause.
    mutating func tick(at now: Date) {
        guard autoPauseEnabled, state == .running, let lastMovementAt else { return }
        guard now.timeIntervalSince(lastMovementAt) >= autoPauseDelay, smoother.currentSpeed(at: now) == nil else { return }
        // Stop the clock where movement stopped, not when we noticed.
        stopMovingClock(at: max(lastMovementAt, movingSince ?? lastMovementAt))
        state = .autoPaused
        smoother.reset()
    }

    /// Restores the route after relaunch and pauses at the last snapshot,
    /// so time while the app wasn't running doesn't count as moving.
    mutating func recover(segments: [[RoutePoint]]) {
        self.segments = segments.isEmpty ? [[]] : segments
        if state != .paused {
            pause(at: savedAt ?? lastMovementAt ?? startDate)
        }
    }

    // MARK: Private

    private mutating func stopMovingClock(at time: Date) {
        if let movingSince {
            accumulatedMovingTime += max(0, time.timeIntervalSince(movingSince))
        }
        movingSince = nil
    }

    private mutating func startNewSegment() {
        if segments.last?.isEmpty == false {
            segments.append([])
        }
    }
}
