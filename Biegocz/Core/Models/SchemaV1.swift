import Foundation
import SwiftData

/// Version 1 of the persisted schema.
///
/// Never change these models in place. A schema change means a new
/// `SchemaV2` (copy the models, then change them) plus a migration stage
/// in `BiegoczMigrationPlan`.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Exercise.self, Activity.self, WorkoutExercise.self, ExerciseSet.self]
    }

    @Model
    final class Exercise {
        var id: UUID = UUID()
        /// Stable key for built-in exercises, `nil` for custom ones.
        var builtInKey: String?
        /// Name of a custom exercise, stored exactly as typed.
        var customName: String?
        var muscleGroupRaw: String = MuscleGroup.chest.rawValue
        var loggingTypeRaw: String = LoggingType.weightReps.rawValue
        var isArchived: Bool = false
        var createdAt: Date = Date.now

        @Relationship(deleteRule: .nullify, inverse: \WorkoutExercise.exercise)
        var workoutEntries: [WorkoutExercise] = []

        init(
            builtInKey: String? = nil,
            customName: String? = nil,
            muscleGroup: MuscleGroup,
            loggingType: LoggingType
        ) {
            self.builtInKey = builtInKey
            self.customName = customName
            self.muscleGroupRaw = muscleGroup.rawValue
            self.loggingTypeRaw = loggingType.rawValue
        }
    }

    /// A gym workout, run or ride.
    @Model
    final class Activity {
        var id: UUID = UUID()
        var typeRaw: String = ActivityType.gym.rawValue
        var startDate: Date = Date.now
        var endDate: Date?
        /// `false` while the session is in progress. Unfinished sessions are
        /// offered for Resume / Save / Discard on launch.
        var isFinished: Bool = false
        var note: String = ""
        /// UUID of the workout saved to HealthKit, to never save it twice.
        var healthKitWorkoutID: UUID?

        /// Wall-clock time from start to finish, including pauses.
        var elapsedSeconds: Double = 0
        /// Time spent moving (cardio) or not paused.
        var movingSeconds: Double = 0
        var distanceMeters: Double = 0
        var elevationGainMeters: Double?
        /// Route points encoded with `RouteCodec`.
        @Attribute(.externalStorage) var routeData: Data?
        /// Encoded in-progress session state for crash recovery.
        var liveStateData: Data?

        @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.activity)
        var exercises: [WorkoutExercise] = []

        init(type: ActivityType, startDate: Date = .now) {
            self.typeRaw = type.rawValue
            self.startDate = startDate
        }
    }

    /// One exercise within a gym workout.
    @Model
    final class WorkoutExercise {
        var id: UUID = UUID()
        var order: Int = 0
        var exercise: Exercise?
        var activity: Activity?

        @Relationship(deleteRule: .cascade, inverse: \ExerciseSet.workoutExercise)
        var sets: [ExerciseSet] = []

        init(exercise: Exercise, order: Int) {
            self.exercise = exercise
            self.order = order
        }
    }

    @Model
    final class ExerciseSet {
        var id: UUID = UUID()
        var order: Int = 0
        var weightKg: Double?
        var reps: Int?
        var durationSeconds: Double?
        var isDone: Bool = false
        var completedAt: Date?
        var workoutExercise: WorkoutExercise?

        init(order: Int, weightKg: Double? = nil, reps: Int? = nil, durationSeconds: Double? = nil) {
            self.order = order
            self.weightKg = weightKg
            self.reps = reps
            self.durationSeconds = durationSeconds
        }
    }
}

typealias Exercise = SchemaV1.Exercise
typealias Activity = SchemaV1.Activity
typealias WorkoutExercise = SchemaV1.WorkoutExercise
typealias ExerciseSet = SchemaV1.ExerciseSet
