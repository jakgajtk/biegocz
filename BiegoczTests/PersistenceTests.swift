import Foundation
import SwiftData
import Testing
@testable import Biegocz

@MainActor
struct PersistenceTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
    }

    @Test func seedingInsertsEveryBuiltInOnce() throws {
        try ExerciseSeeder.seedIfNeeded(in: context)
        try ExerciseSeeder.seedIfNeeded(in: context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        #expect(exercises.count == BuiltInExercises.all.count)
    }

    @Test func seedingLeavesCustomExercisesAlone() throws {
        context.insert(Exercise(customName: "Wiosłowanie T-bar", muscleGroup: .back, loggingType: .weightReps))
        try ExerciseSeeder.seedIfNeeded(in: context)
        let custom = try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.builtInKey == nil }))
        #expect(custom.count == 1)
        #expect(custom.first?.displayName == "Wiosłowanie T-bar")
    }

    @Test func deletingAnActivityDeletesItsSetsButKeepsExercises() throws {
        try ExerciseSeeder.seedIfNeeded(in: context)
        let exercise = try #require(try context.fetch(FetchDescriptor<Exercise>()).first)
        let activity = Activity(type: .gym)
        context.insert(activity)
        let entry = WorkoutExercise(exercise: exercise, order: 0)
        activity.exercises.append(entry)
        entry.sets.append(ExerciseSet(order: 0, weightKg: 80, reps: 8))
        try context.save()

        context.delete(activity)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<ExerciseSet>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutExercise>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == BuiltInExercises.all.count)
    }

    @Test func volumeCountsOnlyCompletedSets() throws {
        let exercise = Exercise(builtInKey: "bench_press", muscleGroup: .chest, loggingType: .weightReps)
        context.insert(exercise)
        let activity = Activity(type: .gym)
        context.insert(activity)
        let entry = WorkoutExercise(exercise: exercise, order: 0)
        activity.exercises.append(entry)
        let done = ExerciseSet(order: 0, weightKg: 80, reps: 8)
        done.isDone = true
        entry.sets.append(done)
        entry.sets.append(ExerciseSet(order: 1, weightKg: 80, reps: 8))

        #expect(activity.totalVolumeKg == 640)
        #expect(activity.completedSetCount == 1)
    }
}
