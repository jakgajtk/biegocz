import Foundation
import SwiftData

/// A live run or ride. Feeds location fixes into `CardioEngine` and
/// persists the state and route every ~10 seconds for crash recovery.
@MainActor
@Observable
final class CardioSessionModel {
    static let persistInterval: TimeInterval = 10

    let activity: Activity
    private(set) var engine: CardioEngine
    /// Drives the UI clock; updated every second.
    private(set) var now: Date
    /// Last valid fix, for the map marker.
    private(set) var lastFix: RoutePoint?
    private(set) var isFinished = false

    private let context: ModelContext
    private let location: any LocationProvider
    private var locationTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var lastPersist = Date.distantPast

    private init(activity: Activity, engine: CardioEngine, context: ModelContext, location: any LocationProvider, now: Date) {
        self.activity = activity
        self.engine = engine
        self.context = context
        self.location = location
        self.now = now
    }

    static func start(
        _ type: ActivityType,
        in context: ModelContext,
        location: any LocationProvider,
        autoPause: Bool,
        now: Date = .now
    ) -> CardioSessionModel {
        let activity = Activity(type: type, startDate: now)
        context.insert(activity)
        let engine = CardioEngine(activityType: type, startDate: now, autoPauseEnabled: autoPause)
        let model = CardioSessionModel(activity: activity, engine: engine, context: context, location: location, now: now)
        model.persist()
        return model
    }

    /// Rebuilds an unfinished session from its last snapshot, paused.
    static func recover(_ activity: Activity, in context: ModelContext, location: any LocationProvider) -> CardioSessionModel {
        var engine = activity.liveStateData
            .flatMap { try? JSONDecoder().decode(CardioEngine.self, from: $0) }
            ?? CardioEngine(activityType: activity.type, startDate: activity.startDate)
        engine.recover(segments: activity.routeSegments)
        let model = CardioSessionModel(activity: activity, engine: engine, context: context, location: location, now: .now)
        model.lastFix = activity.routePoints.last
        return model
    }

    var type: ActivityType { activity.type }

    // MARK: Tracking

    func startTracking() {
        guard locationTask == nil else { return }
        let updates = location.locationUpdates(for: type)
        locationTask = Task { [weak self] in
            for await point in updates {
                self?.handle(point, receivedAt: .now)
            }
        }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick(at: .now)
            }
        }
    }

    func stopTracking() {
        locationTask?.cancel()
        clockTask?.cancel()
        locationTask = nil
        clockTask = nil
    }

    func handle(_ point: RoutePoint, receivedAt time: Date) {
        if point.horizontalAccuracy >= 0 {
            lastFix = point
        }
        engine.ingest(point, receivedAt: time)
        persistIfDue(at: time)
    }

    func tick(at time: Date) {
        now = time
        engine.tick(at: time)
        persistIfDue(at: time)
    }

    // MARK: Controls

    func pause(at time: Date = .now) {
        engine.pause(at: time)
        now = time
        persist(at: time)
    }

    func resume(at time: Date = .now) {
        engine.resume(at: time)
        now = time
        persist(at: time)
    }

    /// Saves the activity as finished. `time` defaults to now; recovery passes the last snapshot.
    func finish(at time: Date = .now) {
        stopTracking()
        let end = time
        engine.pause(at: end)
        now = end
        activity.endDate = end
        activity.elapsedSeconds = engine.elapsedTime(at: end)
        activity.movingSeconds = engine.movingTime(at: end)
        activity.distanceMeters = engine.distance
        activity.routeData = RouteCodec.encode(segments: engine.segments)
        activity.liveStateData = nil
        activity.isFinished = true
        try? context.save()
        isFinished = true
    }

    func discard() {
        stopTracking()
        context.delete(activity)
        try? context.save()
    }

    // MARK: Persistence

    private func persistIfDue(at time: Date) {
        if time.timeIntervalSince(lastPersist) >= Self.persistInterval {
            persist(at: time)
        }
    }

    private func persist(at time: Date = .now) {
        engine.savedAt = time
        activity.distanceMeters = engine.distance
        activity.elapsedSeconds = engine.elapsedTime(at: time)
        activity.movingSeconds = engine.movingTime(at: time)
        activity.routeData = RouteCodec.encode(segments: engine.segments)
        activity.liveStateData = try? JSONEncoder().encode(engine)
        try? context.save()
        lastPersist = time
    }
}
