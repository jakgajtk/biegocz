import Foundation
import SwiftData
import Testing
@testable import Biegocz

@MainActor
struct CardioSessionModelTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
    }

    private func feed(_ model: CardioSessionModel, seconds: Int, speed: Double = 3, from offset: TimeInterval = 0) {
        for p in TestSupport.straightLine(seconds: seconds, speed: speed, start: start.addingTimeInterval(offset)) {
            model.handle(p, receivedAt: p.timestamp)
            model.tick(at: p.timestamp)
        }
    }

    @Test func persistsAboutEveryTenSeconds() throws {
        let model = CardioSessionModel.start(.run, in: context, location: SilentLocationProvider(), health: NoOpHealthStore(), autoPause: false, now: start)
        feed(model, seconds: 25)

        #expect(model.activity.liveStateData != nil)
        #expect(!model.activity.isFinished)
        // Snapshot at 20 s, not 25 s.
        #expect(model.activity.movingSeconds == 20)
        #expect(model.activity.routePoints.count > 10)
    }

    @Test func pauseStopsTheClockAndTellsTheLocationProvider() {
        let location = PauseRecordingLocationProvider()
        let model = CardioSessionModel.start(.run, in: context, location: location, health: NoOpHealthStore(), autoPause: false, now: start)
        feed(model, seconds: 60)
        model.pause(at: start.addingTimeInterval(60))
        // Still moving along while paused: nothing counts.
        feed(model, seconds: 60, from: 60)
        #expect(model.engine.movingTime(at: start.addingTimeInterval(120)) == 60)
        #expect(abs(model.engine.distance - 180) < 10)
        model.resume(at: start.addingTimeInterval(120))
        #expect(location.pauses == [true, false])
    }

    @Test func finishSavesTotalsAndClearsLiveState() {
        let model = CardioSessionModel.start(.run, in: context, location: SilentLocationProvider(), health: NoOpHealthStore(), autoPause: false, now: start)
        feed(model, seconds: 120)
        model.finish(at: start.addingTimeInterval(120))

        #expect(model.activity.isFinished)
        #expect(model.activity.liveStateData == nil)
        #expect(model.activity.elapsedSeconds == 120)
        #expect(abs(model.activity.distanceMeters - 360) < 10)
        #expect(model.activity.routePoints.count == model.engine.routePointCount)
    }

    @Test func crashRecoveryResumesPausedFromLastSnapshot() throws {
        let model = CardioSessionModel.start(.run, in: context, location: SilentLocationProvider(), health: NoOpHealthStore(), autoPause: false, now: start)
        feed(model, seconds: 35)
        let activityID = model.activity.id
        // The app dies here: anything after the 30 s snapshot is lost.

        let coordinator = SessionCoordinator(restNotifier: NoOpRestNotifier(), location: SilentLocationProvider(), health: NoOpHealthStore())
        coordinator.findRecoverable(in: context)
        let recoverable = try #require(coordinator.recoverable)
        #expect(recoverable.id == activityID)

        let recovered = CardioSessionModel.recover(recoverable, in: context, location: SilentLocationProvider(), health: NoOpHealthStore())
        #expect(recovered.engine.state == .paused)
        #expect(recovered.engine.movingTime(at: .now) == 30)
        #expect(abs(recovered.engine.distance - 90) < 10)
    }

    @Test func saveFromRecoveryEndsAtLastSnapshot() throws {
        let model = CardioSessionModel.start(.ride, in: context, location: SilentLocationProvider(), health: NoOpHealthStore(), autoPause: false, now: start)
        feed(model, seconds: 45, speed: 7)

        let coordinator = SessionCoordinator(restNotifier: NoOpRestNotifier(), location: SilentLocationProvider(), health: NoOpHealthStore())
        coordinator.findRecoverable(in: context)
        coordinator.saveRecoverable(in: context)

        #expect(model.activity.isFinished)
        #expect(model.activity.elapsedSeconds == 40)
        #expect(model.activity.endDate == start.addingTimeInterval(40))
    }

    @Test func discardDeletesTheActivity() throws {
        let model = CardioSessionModel.start(.run, in: context, location: SilentLocationProvider(), health: NoOpHealthStore(), autoPause: false, now: start)
        feed(model, seconds: 15)
        model.discard()
        #expect(try context.fetchCount(FetchDescriptor<Activity>()) == 0)
    }
}
