import Foundation
import SwiftData

/// Restores data from a JSON export. Merges: anything already in the app
/// (matched by id) is left untouched, so importing twice changes nothing.
enum DataImporter {
    struct Result: Equatable {
        var activitiesAdded = 0
        var activitiesSkipped = 0
        var exercisesAdded = 0
    }

    enum ImportError: Error {
        case unreadable
        case newerFormat
    }

    static func decode(_ data: Data) throws -> ExportDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let document = try? decoder.decode(ExportDocument.self, from: data) else {
            throw ImportError.unreadable
        }
        guard document.formatVersion <= ExportDocument.currentFormatVersion else {
            throw ImportError.newerFormat
        }
        return document
    }

    @MainActor
    static func importData(_ data: Data, into context: ModelContext) throws -> Result {
        try importDocument(decode(data), into: context)
    }

    @MainActor
    static func importDocument(_ document: ExportDocument, into context: ModelContext) throws -> Result {
        var result = Result()
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        var byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let byKey = Dictionary(
            exercises.compactMap { exercise in exercise.builtInKey.map { ($0, exercise) } },
            uniquingKeysWith: { first, _ in first }
        )

        // Map every exported exercise to a local one: built-ins by key, custom ones by id.
        var resolved: [UUID: Exercise] = [:]
        for record in document.exercises {
            if let key = record.builtInKey, let local = byKey[key] {
                resolved[record.id] = local
            } else if let local = byID[record.id] {
                resolved[record.id] = local
            } else {
                let exercise = Exercise(
                    builtInKey: record.builtInKey,
                    customName: record.customName ?? (record.builtInKey == nil ? record.name : nil),
                    muscleGroup: MuscleGroup(rawValue: record.muscleGroup) ?? .chest,
                    loggingType: LoggingType(rawValue: record.loggingType) ?? .weightReps
                )
                exercise.id = record.id
                exercise.isArchived = record.isArchived
                exercise.createdAt = record.createdAt
                context.insert(exercise)
                byID[record.id] = exercise
                resolved[record.id] = exercise
                result.exercisesAdded += 1
            }
        }

        let existingActivities = Set(try context.fetch(FetchDescriptor<Activity>()).map(\.id))
        for record in document.activities {
            // Unfinished sessions aren't restored; they can't be resumed anyway.
            guard record.isFinished, !existingActivities.contains(record.id) else {
                result.activitiesSkipped += 1
                continue
            }
            let activity = Activity(type: ActivityType(rawValue: record.type) ?? .gym, startDate: record.startDate)
            activity.id = record.id
            activity.endDate = record.endDate
            activity.isFinished = true
            activity.note = record.note
            activity.healthKitWorkoutID = record.healthKitWorkoutID
            activity.elapsedSeconds = record.elapsedSeconds
            activity.movingSeconds = record.movingSeconds
            activity.distanceMeters = record.distanceMeters
            activity.elevationGainMeters = record.elevationGainMeters
            if !record.route.isEmpty {
                activity.routeData = RouteCodec.encode(segments: segments(of: record.route, starts: record.routeSegmentStarts))
            }
            context.insert(activity)

            for entryRecord in record.exercises {
                guard let exercise = entryRecord.exerciseID.flatMap({ resolved[$0] }) else { continue }
                let entry = WorkoutExercise(exercise: exercise, order: entryRecord.order)
                entry.id = entryRecord.id
                activity.exercises.append(entry)
                for setRecord in entryRecord.sets {
                    let set = ExerciseSet(
                        order: setRecord.order,
                        weightKg: setRecord.weightKg,
                        reps: setRecord.reps,
                        durationSeconds: setRecord.durationSeconds
                    )
                    set.id = setRecord.id
                    set.isDone = setRecord.isDone
                    set.completedAt = setRecord.completedAt
                    entry.sets.append(set)
                }
            }
            result.activitiesAdded += 1
        }

        try context.save()
        return result
    }

    static func segments(of route: [RoutePoint], starts: [Int]?) -> [[RoutePoint]] {
        guard let starts, !starts.isEmpty else { return [route] }
        let bounds = (starts + [route.count]).map { min(max($0, 0), route.count) }
        return zip(bounds, bounds.dropFirst()).compactMap { start, end in
            start < end ? Array(route[start..<end]) : nil
        }
    }
}
