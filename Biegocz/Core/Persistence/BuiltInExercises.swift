import Foundation

/// The seeded exercise library. Display names live in `Localizable.xcstrings`
/// under `exercise.<key>`. Keys are stable and must never change.
enum BuiltInExercises {
    struct Definition: Sendable {
        let key: String
        let muscleGroup: MuscleGroup
        let loggingType: LoggingType
    }

    static let all: [Definition] = [
        // Chest
        .init(key: "bench_press", muscleGroup: .chest, loggingType: .weightReps),
        .init(key: "incline_bench_press", muscleGroup: .chest, loggingType: .weightReps),
        .init(key: "dumbbell_bench_press", muscleGroup: .chest, loggingType: .weightReps),
        .init(key: "incline_dumbbell_press", muscleGroup: .chest, loggingType: .weightReps),
        .init(key: "dumbbell_fly", muscleGroup: .chest, loggingType: .weightReps),
        .init(key: "cable_crossover", muscleGroup: .chest, loggingType: .weightReps),
        .init(key: "push_up", muscleGroup: .chest, loggingType: .bodyweightReps),
        .init(key: "dips", muscleGroup: .chest, loggingType: .bodyweightReps),
        // Back
        .init(key: "deadlift", muscleGroup: .back, loggingType: .weightReps),
        .init(key: "pull_up", muscleGroup: .back, loggingType: .bodyweightReps),
        .init(key: "chin_up", muscleGroup: .back, loggingType: .bodyweightReps),
        .init(key: "barbell_row", muscleGroup: .back, loggingType: .weightReps),
        .init(key: "dumbbell_row", muscleGroup: .back, loggingType: .weightReps),
        .init(key: "lat_pulldown", muscleGroup: .back, loggingType: .weightReps),
        .init(key: "seated_cable_row", muscleGroup: .back, loggingType: .weightReps),
        .init(key: "back_extension", muscleGroup: .back, loggingType: .bodyweightReps),
        // Legs
        .init(key: "back_squat", muscleGroup: .legs, loggingType: .weightReps),
        .init(key: "front_squat", muscleGroup: .legs, loggingType: .weightReps),
        .init(key: "romanian_deadlift", muscleGroup: .legs, loggingType: .weightReps),
        .init(key: "leg_press", muscleGroup: .legs, loggingType: .weightReps),
        .init(key: "lunge", muscleGroup: .legs, loggingType: .weightReps),
        .init(key: "bulgarian_split_squat", muscleGroup: .legs, loggingType: .weightReps),
        .init(key: "leg_extension", muscleGroup: .legs, loggingType: .weightReps),
        .init(key: "leg_curl", muscleGroup: .legs, loggingType: .weightReps),
        .init(key: "hip_thrust", muscleGroup: .legs, loggingType: .weightReps),
        .init(key: "calf_raise", muscleGroup: .legs, loggingType: .weightReps),
        // Shoulders
        .init(key: "overhead_press", muscleGroup: .shoulders, loggingType: .weightReps),
        .init(key: "dumbbell_shoulder_press", muscleGroup: .shoulders, loggingType: .weightReps),
        .init(key: "lateral_raise", muscleGroup: .shoulders, loggingType: .weightReps),
        .init(key: "rear_delt_fly", muscleGroup: .shoulders, loggingType: .weightReps),
        .init(key: "face_pull", muscleGroup: .shoulders, loggingType: .weightReps),
        // Arms
        .init(key: "barbell_curl", muscleGroup: .arms, loggingType: .weightReps),
        .init(key: "dumbbell_curl", muscleGroup: .arms, loggingType: .weightReps),
        .init(key: "hammer_curl", muscleGroup: .arms, loggingType: .weightReps),
        .init(key: "triceps_pushdown", muscleGroup: .arms, loggingType: .weightReps),
        .init(key: "skull_crusher", muscleGroup: .arms, loggingType: .weightReps),
        .init(key: "overhead_triceps_extension", muscleGroup: .arms, loggingType: .weightReps),
        // Core
        .init(key: "plank", muscleGroup: .core, loggingType: .duration),
        .init(key: "side_plank", muscleGroup: .core, loggingType: .duration),
        .init(key: "hanging_leg_raise", muscleGroup: .core, loggingType: .bodyweightReps),
        .init(key: "crunch", muscleGroup: .core, loggingType: .bodyweightReps),
        .init(key: "cable_crunch", muscleGroup: .core, loggingType: .weightReps),
        .init(key: "ab_wheel_rollout", muscleGroup: .core, loggingType: .bodyweightReps),
        .init(key: "russian_twist", muscleGroup: .core, loggingType: .bodyweightReps),
    ]

    static func localizationKey(for key: String) -> String {
        "exercise.\(key)"
    }

    static func localizedName(forKey key: String, bundle: Bundle = .main, locale: Locale = .current) -> String {
        String(localized: String.LocalizationValue(localizationKey(for: key)), bundle: bundle, locale: locale)
    }
}
