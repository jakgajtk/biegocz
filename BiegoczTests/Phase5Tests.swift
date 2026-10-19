import Foundation
import SwiftData
import Testing
@testable import Biegocz

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

struct AutoPauseTests {
    /// Moves north at `speed` from `fromSecond` to `toSecond`, starting at `startMeters`.
    private func moving(from fromSecond: Int, to toSecond: Int, speed: Double, startMeters: Double) -> [RoutePoint] {
        (fromSecond...toSecond).map { second in
            RoutePoint(
                latitude: 52.2 + (startMeters + Double(second - fromSecond) * speed) / 111_195,
                longitude: 21,
                altitude: 100,
                timestamp: t0.addingTimeInterval(Double(second)),
                horizontalAccuracy: 5
            )
        }
    }

    /// Stands still with ±2 m GPS drift.
    private func standing(from fromSecond: Int, to toSecond: Int, at meters: Double) -> [RoutePoint] {
        (fromSecond...toSecond).map { second in
            RoutePoint(
                latitude: 52.2 + (meters + (second.isMultiple(of: 2) ? 2 : -2)) / 111_195,
                longitude: 21,
                altitude: 100,
                timestamp: t0.addingTimeInterval(Double(second)),
                horizontalAccuracy: 5
            )
        }
    }

    private func feed(_ engine: inout CardioEngine, _ points: [RoutePoint]) {
        for p in points {
            engine.ingest(p, receivedAt: p.timestamp)
            engine.tick(at: p.timestamp)
        }
    }

    @Test func pausesAtAStopAndExcludesItFromMovingTime() {
        var engine = CardioEngine(activityType: .ride, startDate: t0, autoPauseEnabled: true)
        feed(&engine, moving(from: 0, to: 60, speed: 7, startMeters: 0))
        feed(&engine, standing(from: 61, to: 120, at: 420))
        #expect(engine.state == .autoPaused)
        #expect(engine.currentSpeed(at: t0.addingTimeInterval(120)) == nil)

        feed(&engine, moving(from: 121, to: 180, speed: 7, startMeters: 420))
        #expect(engine.state == .running)

        let end = t0.addingTimeInterval(180)
        // About 60 s of the 180 s were spent standing; resuming takes a few
        // seconds to confirm real movement.
        #expect(engine.movingTime(at: end) < 125)
        #expect(engine.movingTime(at: end) > 108)
        #expect(engine.elapsedTime(at: end) == 180)
        #expect(engine.segments.count == 2)
    }

    @Test func gpsDriftWhileStoppedDoesNotResume() {
        var engine = CardioEngine(activityType: .run, startDate: t0, autoPauseEnabled: true)
        feed(&engine, moving(from: 0, to: 60, speed: 3, startMeters: 0))
        feed(&engine, standing(from: 61, to: 300, at: 180))
        #expect(engine.state == .autoPaused)
    }

    @Test func disabledAutoPauseKeepsRunning() {
        var engine = CardioEngine(activityType: .run, startDate: t0, autoPauseEnabled: false)
        feed(&engine, moving(from: 0, to: 60, speed: 3, startMeters: 0))
        feed(&engine, standing(from: 61, to: 200, at: 180))
        #expect(engine.state == .running)
        #expect(engine.movingTime(at: t0.addingTimeInterval(200)) == 200)
    }

    @Test func defaultsAreOffForRunsAndOnForRides() throws {
        let defaults = try #require(UserDefaults(suiteName: "AutoPauseTests-\(UUID())"))
        #expect(!AppSettings.autoPause(for: .run, defaults: defaults))
        #expect(AppSettings.autoPause(for: .ride, defaults: defaults))
        defaults.set(true, forKey: AppSettings.autoPauseRunKey)
        #expect(AppSettings.autoPause(for: .run, defaults: defaults))
    }
}

struct ElevationGainTests {
    @Test func countsClimbsAndIgnoresDescents() {
        var gain = ElevationGain(threshold: 1)
        for altitude in [100.0, 102, 105, 103, 101, 104, 110] { gain.add(altitude: altitude) }
        // +5 (100→105), then from the 101 trough +9 (101→110).
        #expect(gain.total == 14)
    }

    @Test func noiseBelowThresholdAddsNothing() {
        var gain = ElevationGain(threshold: 4)
        for i in 0..<200 { gain.add(altitude: 100 + (i.isMultiple(of: 2) ? 1.5 : -1.5)) }
        #expect(gain.total == 0)
    }

    @Test func sampleRunClimbIsPlausible() throws {
        // The sample loop rises and falls by 6 m twice: about 24 m of climbing.
        let points = try TestSupport.sampleRoute("SampleRun")
        var engine = CardioEngine(activityType: .run, startDate: points[0].timestamp)
        for p in points { engine.ingest(p, receivedAt: p.timestamp) }
        #expect(engine.elevationGain > 15 && engine.elevationGain < 30, "gain \(engine.elevationGain)")
    }

    @Test func barometerReplacesGPSAltitude() {
        var engine = CardioEngine(activityType: .ride, startDate: t0)
        engine.useBarometer()
        for altitude in [0.0, 2, 4, 6] { engine.ingestBarometricAltitude(altitude) }
        // GPS altitude jumps are ignored once the barometer is in use.
        engine.ingest(RoutePoint(latitude: 52.2, longitude: 21, altitude: 500, timestamp: t0, horizontalAccuracy: 5), receivedAt: t0)
        #expect(engine.elevationGain == 6)
    }

    @Test func polishElevationFormatting() {
        #expect(TestSupport.normalizingSpaces(Formatters.elevation(meters: 42.4, locale: TestSupport.polish)) == "42 m")
    }
}

@MainActor
struct ImportTests {
    private func makeContainer() throws -> ModelContainer {
        let container = try PersistenceController.makeContainer(inMemory: true)
        try ExerciseSeeder.seedIfNeeded(in: container.mainContext)
        return container
    }

    /// A store with a gym workout (built-in + custom exercise), a paused run and an unfinished ride.
    private func populatedExport() throws -> Data {
        let container = try makeContainer()
        let context = container.mainContext
        let bench = try #require(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.builtInKey == "bench_press" })).first)
        let custom = Exercise(customName: "Wyciskanie Larsena", muscleGroup: .chest, loggingType: .weightReps)
        context.insert(custom)

        let gym = GymSessionModel.start(in: context, notifier: NoOpRestNotifier(), restDuration: 120, now: t0)
        gym.addExercise(bench)
        gym.addExercise(custom)
        gym.entries[0].sortedSets[0].values = SetValues(weightKg: 80, reps: 5)
        gym.entries[1].sortedSets[0].values = SetValues(weightKg: 60, reps: 8)
        for entry in gym.entries { gym.toggleDone(entry.sortedSets[0], now: t0) }
        gym.activity.note = "Dobry dzień"
        gym.finish(now: t0.addingTimeInterval(3_600))

        let run = CardioSessionModel.start(.run, in: context, location: SilentLocationProvider(), health: NoOpHealthStore(), autoPause: false, now: t0)
        for p in TestSupport.straightLine(seconds: 60, speed: 3, start: t0) { run.handle(p, receivedAt: p.timestamp) }
        run.pause(at: t0.addingTimeInterval(60))
        run.resume(at: t0.addingTimeInterval(100))
        for p in TestSupport.straightLine(seconds: 60, speed: 3, start: t0.addingTimeInterval(100)) {
            var shifted = p
            shifted.latitude += 500 / 111_195
            run.handle(shifted, receivedAt: shifted.timestamp)
        }
        run.finish(at: t0.addingTimeInterval(160))

        _ = CardioSessionModel.start(.ride, in: context, location: SilentLocationProvider(), health: NoOpHealthStore(), autoPause: false, now: t0)

        return try DataExporter.jsonData(for: DataExporter.makeDocument(from: context))
    }

    @Test func restoresEverythingIntoAnEmptyApp() throws {
        let data = try populatedExport()
        let container = try makeContainer()
        let context = container.mainContext

        let result = try DataImporter.importData(data, into: context)
        #expect(result == DataImporter.Result(activitiesAdded: 2, activitiesSkipped: 1, exercisesAdded: 1))

        let activities = try context.fetch(FetchDescriptor<Activity>())
        let gym = try #require(activities.first { $0.type == .gym })
        #expect(gym.note == "Dobry dzień")
        #expect(gym.sortedExercises.map { $0.exercise?.displayName } == [
            BuiltInExercises.localizedName(forKey: "bench_press"), "Wyciskanie Larsena",
        ])
        #expect(gym.sortedExercises[0].sortedSets.first?.values == SetValues(weightKg: 80, reps: 5))
        // Built-ins map onto the seeded ones instead of being duplicated.
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == BuiltInExercises.all.count + 1)

        let run = try #require(activities.first { $0.type == .run })
        #expect(run.routeSegments.count == 2)
        #expect(run.distanceMeters > 300)
    }

    @Test func importingTwiceChangesNothing() throws {
        let data = try populatedExport()
        let container = try makeContainer()
        _ = try DataImporter.importData(data, into: container.mainContext)
        let second = try DataImporter.importData(data, into: container.mainContext)
        #expect(second.activitiesAdded == 0)
        #expect(second.exercisesAdded == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Activity>()) == 2)
    }

    @Test func rejectsOtherFilesAndNewerFormats() throws {
        #expect(throws: DataImporter.ImportError.unreadable) { try DataImporter.decode(Data("{\"hello\": 1}".utf8)) }
        let newer = """
        {"formatVersion": 99, "exportedAt": "2026-10-19T10:00:00Z", "exercises": [], "activities": []}
        """
        #expect(throws: DataImporter.ImportError.newerFormat) { try DataImporter.decode(Data(newer.utf8)) }
    }

    @Test func segmentSplitting() {
        let points = TestSupport.straightLine(seconds: 9, speed: 3, start: t0)
        #expect(DataImporter.segments(of: points, starts: nil).map(\.count) == [10])
        #expect(DataImporter.segments(of: points, starts: [0, 4, 7]).map(\.count) == [4, 3, 3])
    }

    @Test func polishImportMessagePlurals() {
        let bundle = TestSupport.bundle(for: "pl")
        let locale = TestSupport.polish
        #expect(String(localized: "Added \(1) activities.", bundle: bundle, locale: locale) == "Dodano 1 aktywność.")
        #expect(String(localized: "Added \(3) activities.", bundle: bundle, locale: locale) == "Dodano 3 aktywności.")
        #expect(String(localized: "Added \(12) activities.", bundle: bundle, locale: locale) == "Dodano 12 aktywności.")
    }
}
