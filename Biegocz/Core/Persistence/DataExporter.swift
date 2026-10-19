import Foundation
import SwiftData

enum DataExporter {
    static func makeDocument(from context: ModelContext, now: Date = .now) throws -> ExportDocument {
        let exercises = try context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.createdAt)]))
        let activities = try context.fetch(FetchDescriptor<Activity>(sortBy: [SortDescriptor(\.startDate)]))

        return ExportDocument(
            formatVersion: ExportDocument.currentFormatVersion,
            exportedAt: now,
            exercises: exercises.map { exercise in
                ExerciseRecord(
                    id: exercise.id,
                    builtInKey: exercise.builtInKey,
                    customName: exercise.customName,
                    name: exercise.displayName,
                    muscleGroup: exercise.muscleGroupRaw,
                    loggingType: exercise.loggingTypeRaw,
                    isArchived: exercise.isArchived,
                    createdAt: exercise.createdAt
                )
            },
            activities: activities.map { activity in
                let segments = activity.routeSegments
                return ActivityRecord(
                    id: activity.id,
                    type: activity.typeRaw,
                    startDate: activity.startDate,
                    endDate: activity.endDate,
                    isFinished: activity.isFinished,
                    note: activity.note,
                    healthKitWorkoutID: activity.healthKitWorkoutID,
                    elapsedSeconds: activity.elapsedSeconds,
                    movingSeconds: activity.movingSeconds,
                    distanceMeters: activity.distanceMeters,
                    elevationGainMeters: activity.elevationGainMeters,
                    route: segments.flatMap { $0 },
                    routeSegmentStarts: segments.count > 1 ? segmentStarts(of: segments) : nil,
                    exercises: activity.sortedExercises.map { entry in
                        WorkoutExerciseRecord(
                            id: entry.id,
                            order: entry.order,
                            exerciseID: entry.exercise?.id,
                            sets: entry.sortedSets.map { set in
                                SetRecord(
                                    id: set.id,
                                    order: set.order,
                                    weightKg: set.weightKg,
                                    reps: set.reps,
                                    durationSeconds: set.durationSeconds,
                                    isDone: set.isDone,
                                    completedAt: set.completedAt
                                )
                            }
                        )
                    }
                )
            }
        )
    }

    static func jsonData(for document: ExportDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    /// One row per gym set. Machine-readable: fixed English column names,
    /// ISO 8601 dates and `.` as the decimal separator.
    static func gymSetsCSV(for document: ExportDocument) -> String {
        let names = Dictionary(uniqueKeysWithValues: document.exercises.map { ($0.id, $0.name) })
        let dateStyle = Date.ISO8601FormatStyle()
        var lines = ["date,workout_id,exercise,set,weight_kg,reps,duration_s,done"]

        for activity in document.activities where activity.type == ActivityType.gym.rawValue {
            for entry in activity.exercises {
                let name = entry.exerciseID.flatMap { names[$0] } ?? ""
                for set in entry.sets {
                    lines.append([
                        activity.startDate.formatted(dateStyle),
                        activity.id.uuidString,
                        csvEscaped(name),
                        String(set.order + 1),
                        set.weightKg.map { String($0) } ?? "",
                        set.reps.map { String($0) } ?? "",
                        set.durationSeconds.map { String($0) } ?? "",
                        set.isDone ? "1" : "0",
                    ].joined(separator: ","))
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Writes the JSON and CSV files into a fresh temporary folder and returns their URLs.
    static func writeExportFiles(from context: ModelContext, now: Date = .now) throws -> [URL] {
        let document = try makeDocument(from: context, now: now)
        let stamp = now.formatted(.iso8601.year().month().day())
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let jsonURL = directory.appending(path: "Biegocz-\(stamp).json")
        let csvURL = directory.appending(path: "Biegocz-gym-sets-\(stamp).csv")
        try jsonData(for: document).write(to: jsonURL, options: .atomic)
        try Data(gymSetsCSV(for: document).utf8).write(to: csvURL, options: .atomic)
        return [jsonURL, csvURL]
    }

    private static func segmentStarts(of segments: [[RoutePoint]]) -> [Int] {
        var starts: [Int] = []
        var index = 0
        for segment in segments {
            starts.append(index)
            index += segment.count
        }
        return starts
    }

    private static func csvEscaped(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
