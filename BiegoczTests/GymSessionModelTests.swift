import Foundation
import SwiftData
import Testing
@testable import Biegocz

@MainActor
struct GymSessionModelTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let notifier = NoOpRestNotifier()
    private let bench: Exercise
    private let squat: Exercise

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        bench = Exercise(builtInKey: "bench_press", muscleGroup: .chest, loggingType: .weightReps)
        squat = Exercise(builtInKey: "back_squat", muscleGroup: .legs, loggingType: .weightReps)
        container.mainContext.insert(bench)
        container.mainContext.insert(squat)
    }

    private func start(at date: Date = .now) -> GymSessionModel {
        GymSessionModel.start(in: context, notifier: notifier, restDuration: 120, now: date)
    }

    /// Logs and finishes a workout with the given bench sets.
    private func logPastWorkout(_ sets: [SetValues], at date: Date) {
        let model = start(at: date)
        model.addExercise(bench)
        let entry = model.entries[0]
        entry.sets.first?.values = sets[0]
        for values in sets.dropFirst() {
            model.addSet(to: entry)
            entry.sortedSets.last?.values = values
        }
        for set in entry.sets { model.toggleDone(set, now: date) }
        model.finish(now: date.addingTimeInterval(3_600))
    }

    @Test func firstSetIsEmptyWithoutHistory() {
        let model = start()
        model.addExercise(bench)
        #expect(model.entries[0].sortedSets.map(\.values) == [.empty])
    }

    @Test func firstSetCopiesLastSessionAndNextSetCopiesPrevious() {
        logPastWorkout([SetValues(weightKg: 80, reps: 8), SetValues(weightKg: 85, reps: 5)], at: Date(timeIntervalSince1970: 1_000_000))

        let model = start()
        model.addExercise(bench)
        let entry = model.entries[0]
        #expect(entry.sortedSets[0].values == SetValues(weightKg: 80, reps: 8))

        entry.sortedSets[0].values = SetValues(weightKg: 82.5, reps: 7)
        model.addSet(to: entry)
        #expect(entry.sortedSets[1].values == SetValues(weightKg: 82.5, reps: 7))
    }

    @Test func lastTimeHintUsesMostRecentFinishedWorkout() {
        logPastWorkout([SetValues(weightKg: 70, reps: 8)], at: Date(timeIntervalSince1970: 1_000_000))
        logPastWorkout([SetValues(weightKg: 80, reps: 8), SetValues(weightKg: 80, reps: 8)], at: Date(timeIntervalSince1970: 2_000_000))

        let model = start()
        model.addExercise(bench)
        #expect(model.lastTime(for: model.entries[0]) == .uniform(count: 2, values: SetValues(weightKg: 80, reps: 8)))
    }

    @Test func markingSetDoneStartsRestTimerAndNotification() {
        let now = Date(timeIntervalSince1970: 5_000)
        let model = start(at: now)
        model.addExercise(bench)
        model.toggleDone(model.entries[0].sortedSets[0], now: now)

        #expect(model.restTimer?.endDate == now.addingTimeInterval(120))
        #expect(notifier.scheduledDates == [now.addingTimeInterval(120)])

        model.extendRest(now: now)
        #expect(model.restTimer?.endDate == now.addingTimeInterval(150))
        model.skipRest()
        #expect(model.restTimer == nil)
    }

    @Test func undoingDoneClearsCompletionTime() {
        let model = start()
        model.addExercise(bench)
        let set = model.entries[0].sortedSets[0]
        model.toggleDone(set)
        #expect(set.completedAt != nil)
        model.toggleDone(set)
        #expect(set.completedAt == nil)
        #expect(!set.isDone)
    }

    @Test func finishDropsUndoneSetsAndEmptyExercises() throws {
        let start = Date(timeIntervalSince1970: 10_000)
        let model = self.start(at: start)
        model.addExercise(bench)
        model.addExercise(squat)
        let benchEntry = model.entries[0]
        benchEntry.sortedSets[0].values = SetValues(weightKg: 100, reps: 5)
        model.addSet(to: benchEntry)
        model.toggleDone(benchEntry.sortedSets[0], now: start)

        model.finish(now: start.addingTimeInterval(1_800))

        #expect(model.activity.isFinished)
        #expect(model.activity.exercises.count == 1)
        #expect(model.activity.exercises[0].sets.count == 1)
        #expect(model.summary == WorkoutSummary(duration: 1_800, setCount: 1, volumeKg: 500))
        #expect(try context.fetchCount(FetchDescriptor<ExerciseSet>()) == 1)
    }

    @Test func reorderAndRemoveExercises() {
        let model = start()
        model.addExercise(bench)
        model.addExercise(squat)
        model.moveExercises(from: [1], to: 0)
        #expect(model.entries.map { $0.exercise?.builtInKey } == ["back_squat", "bench_press"])

        model.removeExercise(model.entries[0])
        #expect(model.entries.map { $0.exercise?.builtInKey } == ["bench_press"])
        #expect(model.entries[0].order == 0)
    }

    @Test func removeSetRenumbers() {
        let model = start()
        model.addExercise(bench)
        let entry = model.entries[0]
        model.addSet(to: entry)
        model.addSet(to: entry)
        model.removeSet(entry.sortedSets[0], from: entry)
        #expect(entry.sortedSets.map(\.order) == [0, 1])
    }

    @Test func repeatCopiesExercisesAndSetsWithNothingDone() {
        logPastWorkout([SetValues(weightKg: 80, reps: 8), SetValues(weightKg: 85, reps: 6)], at: Date(timeIntervalSince1970: 1_000_000))
        let past = try! #require(try? context.fetch(FetchDescriptor<Activity>(predicate: #Predicate { $0.isFinished })).first)

        let model = GymSessionModel.repeating(past, in: context, notifier: notifier, restDuration: 120)
        #expect(model.entries.count == 1)
        let sets = model.entries[0].sortedSets
        #expect(sets.map(\.values) == [SetValues(weightKg: 80, reps: 8), SetValues(weightKg: 85, reps: 6)])
        #expect(sets.allSatisfy { !$0.isDone })
        #expect(!model.activity.isFinished)
    }

    @Test func discardDeletesEverything() throws {
        let model = start()
        model.addExercise(bench)
        model.discard()
        #expect(try context.fetchCount(FetchDescriptor<Activity>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ExerciseSet>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 2)
    }
}

@MainActor
struct SessionRecoveryTests {
    @Test func unfinishedWorkoutIsOfferedAndSavedAtLastSet() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let exercise = Exercise(builtInKey: "deadlift", muscleGroup: .back, loggingType: .weightReps)
        context.insert(exercise)
        let start = Date(timeIntervalSince1970: 100_000)
        let model = GymSessionModel.start(in: context, notifier: NoOpRestNotifier(), restDuration: 120, now: start)
        model.addExercise(exercise)
        model.toggleDone(model.entries[0].sortedSets[0], now: start.addingTimeInterval(600))

        let coordinator = SessionCoordinator(restNotifier: NoOpRestNotifier(), location: SilentLocationProvider())
        coordinator.findRecoverable(in: context)
        #expect(coordinator.recoverable?.id == model.activity.id)

        coordinator.saveRecoverable(in: context)
        #expect(model.activity.isFinished)
        #expect(model.activity.elapsedSeconds == 600)
    }

    @Test func emptyUnfinishedWorkoutIsDroppedSilently() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        _ = GymSessionModel.start(in: context, notifier: NoOpRestNotifier(), restDuration: 120)

        let coordinator = SessionCoordinator(restNotifier: NoOpRestNotifier(), location: SilentLocationProvider())
        coordinator.findRecoverable(in: context)
        #expect(coordinator.recoverable == nil)
        #expect(try context.fetchCount(FetchDescriptor<Activity>()) == 0)
    }
}
