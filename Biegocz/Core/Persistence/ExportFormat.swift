import Foundation

/// JSON export format. Import (Phase 5) reads this same format, so only add
/// optional fields; bump `formatVersion` for anything incompatible.
struct ExportDocument: Codable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var exportedAt: Date
    var exercises: [ExerciseRecord]
    var activities: [ActivityRecord]
}

struct ExerciseRecord: Codable, Sendable {
    var id: UUID
    var builtInKey: String?
    var customName: String?
    /// Display name at export time, for humans reading the file.
    var name: String
    var muscleGroup: String
    var loggingType: String
    var isArchived: Bool
    var createdAt: Date
}

struct ActivityRecord: Codable, Sendable {
    var id: UUID
    var type: String
    var startDate: Date
    var endDate: Date?
    var isFinished: Bool
    var note: String
    var healthKitWorkoutID: UUID?
    var elapsedSeconds: Double
    var movingSeconds: Double
    var distanceMeters: Double
    var elevationGainMeters: Double?
    var route: [RoutePoint]
    /// Indices into `route` where each segment starts (segments split at pauses).
    /// `nil` when the whole route is one segment.
    var routeSegmentStarts: [Int]?
    var exercises: [WorkoutExerciseRecord]
}

struct WorkoutExerciseRecord: Codable, Sendable {
    var id: UUID
    var order: Int
    var exerciseID: UUID?
    var sets: [SetRecord]
}

struct SetRecord: Codable, Sendable {
    var id: UUID
    var order: Int
    var weightKg: Double?
    var reps: Int?
    var durationSeconds: Double?
    var isDone: Bool
    var completedAt: Date?
}
