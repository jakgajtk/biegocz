import Foundation
import SwiftData
import Testing
@testable import Biegocz

/// Crafted or corrupt files must be rejected or cleaned up, never crash the
/// app, and never store values that crash the screens showing them.
@MainActor
struct ImportHardeningTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
    }

    @Test func gzipExtraFieldPastTheEndIsCorrupt() {
        // FEXTRA + FNAME, with an extra field length of 65535 in an 18-byte file.
        var bytes: [UInt8] = [0x1F, 0x8B, 8, 0x0C, 0, 0, 0, 0, 0, 3, 0xFF, 0xFF]
        bytes += [UInt8](repeating: 0x41, count: 8)
        #expect(throws: Gzip.GzipError.corrupt) { try Gzip.decompress(Data(bytes)) }
    }

    @Test func fitCompressedTimestampNearMaxDoesNotOverflow() throws {
        // Definition: record message with only a timestamp field (253, 4 bytes).
        let definition: [UInt8] = [0x40, 0, 0, 20, 0, 1, 253, 4, 0x86]
        // Data: timestamp 0xFFFFFFFE, then a compressed-timestamp header (offset 0)
        // that rolls over the 32-second window past UInt32.max.
        let data: [UInt8] = [0x00, 0xFE, 0xFF, 0xFF, 0xFF, 0x80, 0xFF, 0xFF, 0xFF, 0xFF]
        let body = definition + data
        let size = UInt32(body.count)
        let header: [UInt8] = [12, 0x10, 0, 0,
                               UInt8(size & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size >> 16 & 0xFF), UInt8(size >> 24),
                               0x2E, 0x46, 0x49, 0x54]
        let track = try FITParser.parse(Data(header + body))
        #expect(track.segments.isEmpty)
    }

    @Test func filterRejectsCoordinatesOffTheGlobe() {
        var filter = LocationFilter(config: .run)
        let bad = [
            RoutePoint(latitude: .nan, longitude: 21, altitude: 0, timestamp: start, horizontalAccuracy: 5),
            RoutePoint(latitude: 52, longitude: 400, altitude: 0, timestamp: start, horizontalAccuracy: 5),
            RoutePoint(latitude: 52, longitude: 21, altitude: .infinity, timestamp: start, horizontalAccuracy: 5),
        ]
        for point in bad {
            #expect(filter.process(point, receivedAt: start) == .rejected(.invalid))
        }
    }

    @Test func implausibleFileTotalsFallBackToTheTrack() throws {
        let points = TestSupport.straightLine(seconds: 600, speed: 3, start: start)
        for total in [Double.infinity, .nan, 1e300, -5] {
            let track = ImportedTrack(sport: .run, segments: [points], distanceMeters: total, movingSeconds: total, elapsedSeconds: total)
            let activity = try #require(TrackImport.activity(from: track))
            #expect(activity.distanceMeters > 1_700 && activity.distanceMeters < 1_900)
            #expect(activity.elapsedSeconds == 600)
            #expect(activity.movingSeconds == 600)
        }
    }

    @Test func formattersShowDashesForUnrepresentableDurations() {
        for seconds in [Double.infinity, .nan, 1e300] {
            #expect(Formatters.duration(seconds: seconds) == "--")
            #expect(Formatters.pace(secondsPerKilometer: seconds) == "--")
        }
        #expect(Formatters.duration(seconds: 65) != "--")
    }

    @Test func setLimitsClampTypedValues() {
        #expect(SetLimits.reps(1e30) == SetLimits.maxReps)
        #expect(SetLimits.reps(-3) == 0)
        #expect(SetLimits.reps(Double.nan) == nil)
        #expect(SetLimits.reps(Int.max) == SetLimits.maxReps)
        #expect(SetLimits.weight(1e300) == SetLimits.maxWeightKg)
        #expect(SetLimits.duration(.infinity) == nil)
    }

    @Test func jsonImportDropsImpossibleValuesAndDuplicateIDs() throws {
        let exerciseID = UUID()
        let activityID = UUID()
        let good = RoutePoint(latitude: 52.2, longitude: 21, altitude: 100, timestamp: start, horizontalAccuracy: 5)
        let bad = RoutePoint(latitude: 952.2, longitude: 21, altitude: 100, timestamp: start, horizontalAccuracy: 5)
        let set = SetRecord(id: UUID(), order: 0, weightKg: 1e300, reps: .max, durationSeconds: nil, isDone: true, completedAt: nil)
        let record = ActivityRecord(
            id: activityID, type: "run", startDate: start, endDate: start, isFinished: true, note: "",
            healthKitWorkoutID: nil, elapsedSeconds: 1e300, movingSeconds: -1, distanceMeters: 5_000,
            elevationGainMeters: 1e300, route: [good, bad], routeSegmentStarts: nil,
            exercises: [WorkoutExerciseRecord(id: UUID(), order: 0, exerciseID: exerciseID, sets: [set])]
        )
        let document = ExportDocument(
            formatVersion: ExportDocument.currentFormatVersion,
            exportedAt: start,
            exercises: [ExerciseRecord(id: exerciseID, builtInKey: nil, customName: "Test", name: "Test",
                                       muscleGroup: "chest", loggingType: "weightReps", isArchived: false, createdAt: start)],
            activities: [record, record]
        )

        let result = try DataImporter.importDocument(document, into: context)
        #expect(result.activitiesAdded == 1)
        #expect(result.activitiesSkipped == 1)

        let activity = try #require(try context.fetch(FetchDescriptor<Activity>()).first)
        #expect(activity.elapsedSeconds == 0)
        #expect(activity.movingSeconds == 0)
        #expect(activity.distanceMeters == 5_000)
        #expect(activity.elevationGainMeters == nil)
        #expect(activity.routeSegments == [[good]])
        let imported = try #require(activity.exercises.first?.sets.first)
        #expect(imported.weightKg == SetLimits.maxWeightKg)
        #expect(imported.reps == SetLimits.maxReps)
    }
}
