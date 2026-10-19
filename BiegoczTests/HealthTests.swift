import Foundation
import SwiftData
import Testing
@testable import Biegocz

/// Records what would be written to Health.
@MainActor
final class FakeHealthStore: HealthStore {
    var isAvailable = true
    var canSaveWorkouts = true
    private(set) var authorizationRequests = 0
    private(set) var saved: [WorkoutRecord] = []
    private(set) var liveWorkouts: [FakeLiveWorkout] = []
    private(set) var abandonedSessionsEnded = 0

    func requestAuthorization() async { authorizationRequests += 1 }

    func startLiveWorkout(_ type: ActivityType, at start: Date) async -> (any LiveWorkout)? {
        guard canSaveWorkouts else { return nil }
        let live = FakeLiveWorkout()
        liveWorkouts.append(live)
        return live
    }

    func saveWorkout(_ record: WorkoutRecord) async throws -> UUID {
        guard canSaveWorkouts else { throw HealthError.notAuthorized }
        saved.append(record)
        return UUID()
    }

    func endAbandonedLiveWorkout() async { abandonedSessionsEnded += 1 }
}

@MainActor
final class FakeLiveWorkout: LiveWorkout {
    private(set) var events: [String] = []
    private(set) var finished: WorkoutRecord?

    func pause(at date: Date) { events.append("pause") }
    func resume(at date: Date) { events.append("resume") }
    func finish(_ record: WorkoutRecord) async throws -> UUID {
        finished = record
        return UUID()
    }
    func discard() { events.append("discard") }
}

struct RouteSummariesTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func lengthMatchesEngineDistanceIncludingReanchorAndPauses() throws {
        var engine = CardioEngine(activityType: .run, startDate: t0)
        let points = try TestSupport.sampleRoute("SampleRun")
        for (index, point) in points.enumerated() {
            if index == 500 { engine.pause(at: point.timestamp) }
            if index == 560 { engine.resume(at: point.timestamp) }
            engine.ingest(point, receivedAt: point.timestamp)
        }
        #expect(abs(RouteSummaries.length(of: engine.segments) - engine.distance) < 0.01)
        #expect(engine.segments.count >= 2)
    }

    @Test func chunksCoverTheDistanceAndNeverSpanAPause() {
        let first = TestSupport.straightLine(seconds: 150, speed: 3, start: t0)
        let second = TestSupport.straightLine(seconds: 90, speed: 3, start: t0.addingTimeInterval(400))
        let segments = [first, second]
        let chunks = RouteSummaries.distanceChunks(of: segments)

        let total = chunks.reduce(0) { $0 + $1.meters }
        #expect(abs(total - RouteSummaries.length(of: segments)) < 0.01)
        #expect(chunks.allSatisfy { $0.end.timeIntervalSince($0.start) <= 60 })
        let pause = DateInterval(start: t0.addingTimeInterval(150), end: t0.addingTimeInterval(400))
        #expect(!chunks.contains { $0.start < pause.end && $0.end > pause.start })
    }

    @Test func pausesAreTheGapsBetweenSegments() {
        let first = TestSupport.straightLine(seconds: 100, speed: 3, start: t0)
        let second = TestSupport.straightLine(seconds: 100, speed: 3, start: t0.addingTimeInterval(300))
        #expect(RouteSummaries.pauses(between: [first, second]) == [
            DateInterval(start: t0.addingTimeInterval(100), end: t0.addingTimeInterval(300)),
        ])
        #expect(RouteSummaries.pauses(between: [first]).isEmpty)
    }
}

@MainActor
struct HealthSyncTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
    }

    private func finishedGymWorkout() -> GymSessionModel {
        let exercise = Exercise(builtInKey: "deadlift", muscleGroup: .back, loggingType: .weightReps)
        context.insert(exercise)
        let model = GymSessionModel.start(in: context, notifier: NoOpRestNotifier(), restDuration: 120, now: start)
        model.addExercise(exercise)
        model.toggleDone(model.entries[0].sortedSets[0], now: start)
        return model
    }

    @Test func gymWorkoutIsSavedOnceAsStrengthTraining() async {
        let health = FakeHealthStore()
        let model = finishedGymWorkout()
        model.health = health
        model.finish(now: start.addingTimeInterval(3_000))
        await model.healthSave?.value

        #expect(health.authorizationRequests == 1)
        #expect(health.saved.count == 1)
        #expect(health.saved.first?.type == .gym)
        #expect(health.saved.first?.end == start.addingTimeInterval(3_000))
        #expect(model.activity.healthKitWorkoutID != nil)

        // A second attempt doesn't create a duplicate.
        await HealthSync.save(model.activity, using: health, context: context)
        #expect(health.saved.count == 1)
    }

    @Test func deniedAccessLeavesTheWorkoutInTheApp() async {
        let health = FakeHealthStore()
        health.canSaveWorkouts = false
        let model = finishedGymWorkout()
        model.health = health
        model.finish(now: start.addingTimeInterval(3_000))
        await model.healthSave?.value

        #expect(model.activity.isFinished)
        #expect(model.activity.healthKitWorkoutID == nil)
        #expect(health.saved.isEmpty)
    }

    @Test func runIsRecordedLiveWithPausesAndFinishedWithRoute() async throws {
        let health = FakeHealthStore()
        let model = CardioSessionModel.start(.run, in: context, location: SilentLocationProvider(), health: health, autoPause: false, now: start)
        // Let the live workout start.
        while health.liveWorkouts.isEmpty { await Task.yield() }
        await Task.yield()

        for p in TestSupport.straightLine(seconds: 60, speed: 3, start: start) { model.handle(p, receivedAt: p.timestamp) }
        model.pause(at: start.addingTimeInterval(60))
        model.resume(at: start.addingTimeInterval(120))
        model.finish(at: start.addingTimeInterval(130))
        await model.healthSave?.value

        let live = try #require(health.liveWorkouts.first)
        #expect(live.events == ["pause", "resume"])
        #expect(live.finished?.type == .run)
        #expect(live.finished?.segments.first?.isEmpty == false)
        #expect(health.saved.isEmpty)
        #expect(model.activity.healthKitWorkoutID != nil)
    }

    @Test func autoPauseIsMirroredToHealth() async throws {
        let health = FakeHealthStore()
        let model = CardioSessionModel.start(.ride, in: context, location: SilentLocationProvider(), health: health, autoPause: true, now: start)
        while health.liveWorkouts.isEmpty { await Task.yield() }
        await Task.yield()

        for p in TestSupport.straightLine(seconds: 60, speed: 7, start: start) {
            model.handle(p, receivedAt: p.timestamp)
            model.tick(at: p.timestamp)
        }
        // Stop at a red light for 40 s.
        let stopPoint = TestSupport.straightLine(seconds: 60, speed: 7, start: start).last!
        for second in 61...100 {
            var p = stopPoint
            p.timestamp = start.addingTimeInterval(Double(second))
            model.handle(p, receivedAt: p.timestamp)
            model.tick(at: p.timestamp)
        }
        #expect(model.engine.state == .autoPaused)
        #expect(health.liveWorkouts.first?.events == ["pause"])
    }

    @Test func recoveredRunIsSavedFromStoredDataAndOldSessionEnded() async throws {
        let health = FakeHealthStore()
        let model = CardioSessionModel.start(.run, in: context, location: SilentLocationProvider(), health: health, autoPause: false, now: start)
        for p in TestSupport.straightLine(seconds: 45, speed: 3, start: start) {
            model.handle(p, receivedAt: p.timestamp)
            model.tick(at: p.timestamp)
        }

        let coordinator = SessionCoordinator(restNotifier: NoOpRestNotifier(), location: SilentLocationProvider(), health: health)
        coordinator.findRecoverable(in: context)
        coordinator.saveRecoverable(in: context)
        // Wait for the background Health work.
        for _ in 0..<50 where health.saved.isEmpty || health.abandonedSessionsEnded == 0 { await Task.yield() }

        #expect(health.abandonedSessionsEnded == 1)
        #expect(health.saved.count == 1)
        #expect(health.saved.first?.end == start.addingTimeInterval(40))
    }

    @Test func discardingARunDiscardsTheHealthWorkout() async {
        let health = FakeHealthStore()
        let model = CardioSessionModel.start(.run, in: context, location: SilentLocationProvider(), health: health, autoPause: false, now: start)
        while health.liveWorkouts.isEmpty { await Task.yield() }
        await Task.yield()
        model.discard()
        #expect(health.liveWorkouts.first?.events == ["discard"])
    }
}
