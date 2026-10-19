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

    var session: ExerciseSession {
        ExerciseSession(
            date: activity?.startDate ?? .distantPast,
            sets: sortedSets.map { LoggedSet(values: $0.values, isDone: $0.isDone) }
        )
    }
}

extension ExerciseSet {
    var values: SetValues {
        get { SetValues(weightKg: weightKg, reps: reps, durationSeconds: durationSeconds) }
        set {
            weightKg = newValue.weightKg
            reps = newValue.reps
            durationSeconds = newValue.durationSeconds
        }
    }
}

extension Exercise {
    /// Entries of this exercise in finished workouts, newest first.
    var finishedEntries: [WorkoutExercise] {
        workoutEntries
            .filter { $0.activity?.isFinished == true }
            .sorted { ($0.activity?.startDate ?? .distantPast) > ($1.activity?.startDate ?? .distantPast) }
    }

    /// The most recent finished session with this exercise, ignoring `activity`.
    func lastSession(excluding activity: Activity? = nil) -> ExerciseSession? {
        finishedEntries.first { $0.activity?.id != activity?.id }?.session
    }
}
