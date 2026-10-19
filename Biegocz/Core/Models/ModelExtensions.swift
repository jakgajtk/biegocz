import Foundation

extension Exercise {
    var muscleGroup: MuscleGroup {
        get { MuscleGroup(rawValue: muscleGroupRaw) ?? .chest }
        set { muscleGroupRaw = newValue.rawValue }
    }

    var loggingType: LoggingType {
        get { LoggingType(rawValue: loggingTypeRaw) ?? .weightReps }
        set { loggingTypeRaw = newValue.rawValue }
    }

    var isCustom: Bool { builtInKey == nil }

    var hasHistory: Bool { !workoutEntries.isEmpty }

    /// Name in the current language for built-ins, as typed for custom ones.
    var displayName: String {
        if let customName { return customName }
        if let builtInKey { return BuiltInExercises.localizedName(forKey: builtInKey) }
        return ""
    }
}

extension Activity {
    var type: ActivityType {
        get { ActivityType(rawValue: typeRaw) ?? .gym }
        set { typeRaw = newValue.rawValue }
    }

    var sortedExercises: [WorkoutExercise] {
        exercises.sorted { $0.order < $1.order }
    }

    var completedSetCount: Int {
        exercises.reduce(0) { $0 + $1.sets.filter(\.isDone).count }
    }

    /// Sum of weight × reps over completed sets.
    var totalVolumeKg: Double {
        var total = 0.0
        for entry in exercises {
            for set in entry.sets where set.isDone {
                let weight = set.weightKg ?? 0
                let reps = Double(set.reps ?? 0)
                total += weight * reps
            }
        }
        return total
    }

    var routePoints: [RoutePoint] {
        guard let routeData else { return [] }
        return (try? RouteCodec.decode(routeData)) ?? []
    }
}

extension WorkoutExercise {
    var sortedSets: [ExerciseSet] {
        sets.sorted { $0.order < $1.order }
    }
}
