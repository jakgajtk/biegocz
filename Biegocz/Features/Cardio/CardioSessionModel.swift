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
    private let health: any HealthStore
    /// Health recording; `nil` without Health access or after crash recovery,
    /// in which case the workout is saved to Health at the end instead.
    private var liveWorkout: (any LiveWorkout)?
    private var locationTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var lastPersist = Date.distantPast

    private init(
        activity: Activity,
        engine: CardioEngine,
        context: ModelContext,
        location: any LocationProvider,
        health: any HealthStore,
        now: Date
    ) {
        self.activity = activity
        self.engine = engine
        self.context = context
        self.location = location
        self.health = health
        self.now = now
    }

    static func start(
        _ type: ActivityType,
        in context: ModelContext,
        location: any LocationProvider,
        health: any HealthStore,
        autoPause: Bool,
        now: Date = .now
    ) -> CardioSessionModel {
        let activity = Activity(type: type, startDate: now)
        context.insert(activity)
        let engine = CardioEngine(activityType: type, startDate: now, autoPauseEnabled: autoPause)
        let model = CardioSessionModel(
            activity: activity, engine: engine, context: context, location: location, health: health, now: now
        )
        model.persist()
        Task { [weak model] in
            let live = await health.startLiveWorkout(type, at: now)
            guard let model, !model.isFinished else {
                live?.discard()
                return
            }
            model.liveWorkout = live
            if model.engine.state != .running {
                live?.pause(at: .now)
            }
        }
        return model
    }

    /// Rebuilds an unfinished session from its last snapshot, paused.
    static func recover(
        _ activity: Activity,
        in context: ModelContext,
        location: any LocationProvider,
        health: any HealthStore
    ) -> CardioSessionModel {
        var engine = activity.liveStateData
            .flatMap { try? JSONDecoder().decode(CardioEngine.self, from: $0) }
            ?? CardioEngine(activityType: activity.type, startDate: activity.startDate)
        engine.recover(segments: activity.routeSegments)
        let model = CardioSessionModel(
            activity: activity, engine: engine, context: context, location: location, health: health, now: .now
        )
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
        let before = engine.state
        engine.ingest(point, receivedAt: time)
        syncHealthState(from: before, at: time)
        persistIfDue(at: time)
    }

    func tick(at time: Date) {
        now = time
        let before = engine.state
        engine.tick(at: time)
        syncHealthState(from: before, at: time)
        persistIfDue(at: time)
    }

    // MARK: Controls

    func pause(at time: Date = .now) {
        let before = engine.state
        engine.pause(at: time)
        now = time
        syncHealthState(from: before, at: time)
        persist(at: time)
    }

    func resume(at time: Date = .now) {
        let before = engine.state
        engine.resume(at: time)
        now = time
        syncHealthState(from: before, at: time)
        persist(at: time)
    }

    /// Mirrors pause / auto-pause into the Health session.
    private func syncHealthState(from before: CardioEngine.State, at time: Date) {
        let wasRunning = before == .running
        let isRunning = engine.state == .running
        if wasRunning && !isRunning {
            liveWorkout?.pause(at: time)
        } else if !wasRunning && isRunning {
            liveWorkout?.resume(at: time)
        }
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

        let live = liveWorkout
        liveWorkout = nil
        guard health.isAvailable else { return }
        healthSave = Task { [activity, health, context] in
            await HealthSync.save(activity, using: health, live: live, context: context)
        }
    }

    /// The pending Health save after `finish`, for tests.
    private(set) var healthSave: Task<Void, Never>?

    func discard() {
        stopTracking()
        liveWorkout?.discard()
        liveWorkout = nil
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
