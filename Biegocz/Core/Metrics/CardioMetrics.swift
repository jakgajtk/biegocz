import Foundation

enum GeoMath {
    static let earthRadius = 6_371_008.8

    /// Great-circle distance in meters (haversine).
    static func distance(_ a: RoutePoint, _ b: RoutePoint) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }
}

/// Signal quality shown before starting.
enum GPSQuality: Equatable, Sendable {
    case none, poor, ok, good

    init(horizontalAccuracy: Double?) {
        guard let accuracy = horizontalAccuracy, accuracy >= 0 else {
            self = .none
            return
        }
        switch accuracy {
        case ...10: self = .good
        case ...25: self = .ok
        default: self = .poor
        }
    }
}

// MARK: - Filtering

/// Thresholds for one activity type.
struct LocationFilterConfig: Equatable, Codable, Sendable {
    /// Fixes less accurate than this (meters) are dropped.
    var maxHorizontalAccuracy: Double = 25
    /// Fixes older than this when they arrive (seconds) are dropped.
    var maxAge: TimeInterval = 10
    /// Jumps implying a faster speed (m/s) are dropped.
    var maxSpeed: Double
    /// Movement (meters) since the last accepted point needed before distance is added.
    var minimumMovement: Double
    /// Below this speed (m/s) the activity counts as not moving.
    var movingSpeed: Double
    /// After this many impossible jumps in a row, the last accepted point is
    /// considered wrong and the next fix becomes the new anchor.
    var maxConsecutiveJumps: Int = 5

    static let run = LocationFilterConfig(maxSpeed: 12, minimumMovement: 5, movingSpeed: 0.8)
    static let ride = LocationFilterConfig(maxSpeed: 25, minimumMovement: 8, movingSpeed: 1.5)

    static func forActivity(_ type: ActivityType) -> LocationFilterConfig {
        type == .ride ? .ride : .run
    }
}

enum FilterDecision: Equatable, Sendable {
    /// Added to the route; `distance` is the meters to add.
    case accepted(distance: Double)
    /// Valid fix, but too close to the last accepted point to count.
    case stationary
    case rejected(Rejection)

    enum Rejection: Equatable, Sendable {
        case invalid, inaccurate, stale, outOfOrder, impossibleSpeed
    }
}

struct LocationFilter: Codable, Equatable, Sendable {
    let config: LocationFilterConfig
    private(set) var lastAccepted: RoutePoint?
    private var consecutiveJumps = 0

    init(config: LocationFilterConfig) {
        self.config = config
    }

    mutating func process(_ point: RoutePoint, receivedAt now: Date) -> FilterDecision {
        guard point.horizontalAccuracy >= 0, point.hasValidCoordinates else { return .rejected(.invalid) }
        guard point.horizontalAccuracy <= config.maxHorizontalAccuracy else { return .rejected(.inaccurate) }
        guard now.timeIntervalSince(point.timestamp) <= config.maxAge else { return .rejected(.stale) }

        guard let last = lastAccepted else {
            lastAccepted = point
            return .accepted(distance: 0)
        }
        let interval = point.timestamp.timeIntervalSince(last.timestamp)
        guard interval > 0 else { return .rejected(.outOfOrder) }

        let distance = GeoMath.distance(last, point)
        if distance / interval > config.maxSpeed {
            consecutiveJumps += 1
            if consecutiveJumps >= config.maxConsecutiveJumps {
                // The anchor itself was probably bad: start over from here, adding nothing.
                consecutiveJumps = 0
                lastAccepted = point
                return .accepted(distance: 0)
            }
            return .rejected(.impossibleSpeed)
        }
        consecutiveJumps = 0

        guard distance >= config.minimumMovement else { return .stationary }
        lastAccepted = point
        return .accepted(distance: distance)
    }

    /// Forget the last point, e.g. after a pause, so no distance bridges the gap.
    mutating func reset() {
        lastAccepted = nil
        consecutiveJumps = 0
    }
}

// MARK: - Speed

/// Current speed over a sliding window of roughly 25 seconds.
struct SpeedSmoother: Codable, Equatable, Sendable {
    struct Sample: Codable, Equatable, Sendable {
        var time: Date
        var distance: Double
    }

    var window: TimeInterval = 25
    /// Shorter spans than this give no reading yet.
    var minimumSpan: TimeInterval = 5
    /// With no fix for this long, the reading is dropped.
    var maxSilence: TimeInterval = 10
    var movingSpeed: Double
    private(set) var samples: [Sample] = []

    init(movingSpeed: Double) {
        self.movingSpeed = movingSpeed
    }

    /// Records the total distance at the time of a (non-rejected) fix.
    mutating func add(time: Date, totalDistance: Double) {
        samples.append(Sample(time: time, distance: totalDistance))
        let cutoff = time.addingTimeInterval(-window)
        // Keep one sample at or before the cutoff so the window stays full.
        if let firstInside = samples.firstIndex(where: { $0.time >= cutoff }), firstInside > 1 {
            samples.removeFirst(firstInside - 1)
        }
    }

    mutating func reset() {
        samples.removeAll()
    }

    /// Meters per second, or `nil` when not moving or there's no reliable reading.
    func currentSpeed(at now: Date) -> Double? {
        guard let last = samples.last, now.timeIntervalSince(last.time) <= maxSilence else { return nil }
        let cutoff = last.time.addingTimeInterval(-window)
        guard let first = samples.last(where: { $0.time <= cutoff }) ?? samples.first else { return nil }
        let span = last.time.timeIntervalSince(first.time)
        guard span >= minimumSpan else { return nil }
        let speed = (last.distance - first.distance) / span
        return speed >= movingSpeed ? speed : nil
    }
}

enum Pace {
    /// Seconds per kilometer for a speed in m/s.
    static func secondsPerKilometer(metersPerSecond speed: Double?) -> Double? {
        guard let speed, speed > 0 else { return nil }
        return 1000 / speed
    }
}

// MARK: - Elevation

/// Total climb with a dead band, so sensor noise doesn't add up.
/// Approximate by nature: barometric readings drift with the weather and
/// GPS altitude is much noisier.
struct ElevationGain: Codable, Equatable, Sendable {
    /// Rises smaller than this (meters) are ignored.
    var threshold: Double
    private(set) var total: Double = 0
    private var reference: Double?

    /// Barometric altitude is precise to about a meter; GPS altitude is not.
    static let barometric = ElevationGain(threshold: 1)
    static let gps = ElevationGain(threshold: 4)

    init(threshold: Double) {
        self.threshold = threshold
    }

    mutating func add(altitude: Double) {
        guard let reference else {
            self.reference = altitude
            return
        }
        if altitude >= reference + threshold {
            total += altitude - reference
            self.reference = altitude
        } else if altitude < reference {
            self.reference = altitude
        }
    }

    /// Forget the last altitude, e.g. after a pause.
    mutating func reset() {
        reference = nil
    }
}

// MARK: - Splits

struct Split: Equatable, Sendable {
    /// 1-based kilometer number.
    var number: Int
    /// 1000 except for the last, partial split.
    var distance: Double
    /// Moving seconds for this split.
    var duration: TimeInterval

    var secondsPerKilometer: Double { duration / distance * 1000 }
}

enum Splits {
    /// Per-kilometer splits from a route split at pauses. Time between
    /// segments (paused) isn't counted. The last split may be partial;
    /// it's dropped if shorter than `minimumLastSplit` meters.
    static func perKilometer(segments: [[RoutePoint]], minimumLastSplit: Double = 50) -> [Split] {
        var splits: [Split] = []
        var distance = 0.0
        var time = 0.0
        var splitStartTime = 0.0
        var nextBoundary = 1000.0

        for segment in segments {
            for (previous, point) in zip(segment, segment.dropFirst()) {
                let stepDistance = GeoMath.distance(previous, point)
                let stepTime = point.timestamp.timeIntervalSince(previous.timestamp)
                guard stepTime > 0 else { continue }
                var covered = 0.0
                while distance + (stepDistance - covered) >= nextBoundary {
                    let needed = nextBoundary - distance
                    covered += needed
                    let crossingTime = time + stepTime * (covered / stepDistance)
                    splits.append(Split(number: splits.count + 1, distance: 1000, duration: crossingTime - splitStartTime))
                    splitStartTime = crossingTime
                    distance = nextBoundary
                    nextBoundary += 1000
                }
                distance += stepDistance - covered
                time += stepTime
            }
        }

        let remaining = distance - (nextBoundary - 1000)
        if remaining >= minimumLastSplit {
            splits.append(Split(number: splits.count + 1, distance: remaining, duration: time - splitStartTime))
        }
        return splits
    }
}
