import Foundation
import SwiftData
import Testing
@testable import Biegocz

@MainActor
struct ExportTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
    }

    private func insertSampleData() throws {
        let custom = Exercise(customName: "Wyciskanie, \"wąsko\"", muscleGroup: .chest, loggingType: .weightReps)
        context.insert(custom)

        let gym = Activity(type: .gym, startDate: Date(timeIntervalSince1970: 1_760_000_000))
        gym.isFinished = true
        context.insert(gym)
        let entry = WorkoutExercise(exercise: custom, order: 0)
        gym.exercises.append(entry)
        let set = ExerciseSet(order: 0, weightKg: 62.5, reps: 8)
        set.isDone = true
        entry.sets.append(set)

        let run = Activity(type: .run, startDate: Date(timeIntervalSince1970: 1_760_100_000))
        run.isFinished = true
        run.distanceMeters = 5_000
        run.routeData = RouteCodec.encode([
            RoutePoint(latitude: 52.2297, longitude: 21.0122, altitude: 100, timestamp: run.startDate, horizontalAccuracy: 5),
        ])
        context.insert(run)
        try context.save()
    }

    @Test func jsonRoundTripsEverything() throws {
        try insertSampleData()
        let document = try DataExporter.makeDocument(from: context)
        let data = try DataExporter.jsonData(for: document)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ExportDocument.self, from: data)

        #expect(decoded.formatVersion == ExportDocument.currentFormatVersion)
        #expect(decoded.exercises.count == 1)
        #expect(decoded.activities.count == 2)
        let gym = try #require(decoded.activities.first { $0.type == "gym" })
        #expect(gym.exercises.first?.sets.first?.weightKg == 62.5)
        #expect(gym.exercises.first?.exerciseID == decoded.exercises.first?.id)
        let run = try #require(decoded.activities.first { $0.type == "run" })
        #expect(run.route.count == 1)
        #expect(run.distanceMeters == 5_000)
    }

    @Test func csvHasOneRowPerGymSetWithEscapedNames() throws {
        try insertSampleData()
        let csv = DataExporter.gymSetsCSV(for: try DataExporter.makeDocument(from: context))
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0] == "date,workout_id,exercise,set,weight_kg,reps,duration_s,done")
        #expect(lines[1].contains("\"Wyciskanie, \"\"wąsko\"\"\",1,62.5,8,,1"))
    }

    @Test func writesBothFiles() throws {
        try insertSampleData()
        let urls = try DataExporter.writeExportFiles(from: context)
        #expect(urls.map(\.pathExtension) == ["json", "csv"])
        for url in urls {
            #expect(FileManager.default.fileExists(atPath: url.path()))
        }
    }
}
