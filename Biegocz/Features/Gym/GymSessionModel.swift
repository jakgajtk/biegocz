import Foundation
import SwiftData

/// Summary shown when a workout is finished.
struct WorkoutSummary: Equatable {
    var duration: TimeInterval
    var setCount: Int
    var volumeKg: Double
}

/// The live gym workout. Every change goes straight into SwiftData, so a
/// crash loses nothing; the activity stays unfinished until `finish()`.
@MainActor
@Observable
final class GymSessionModel {
    let activity: Activity
    private let context: ModelContext
    private let notifier: RestNotifying

    var restDuration: TimeInterval
    private(set) var restTimer: RestTimer?
    private(set) var summary: WorkoutSummary?

    init(activity: Activity, context: ModelContext, notifier: RestNotifying, restDuration: TimeInterval) {
        self.activity = activity
        self.context = context
        self.notifier = notifier
        self.restDuration = restDuration
    }

    /// Starts a new, empty workout.
    static func start(
        in context: ModelContext,
        notifier: RestNotifying,
        restDuration: TimeInterval,
        now: Date = .now
    ) -> GymSessionModel {
        let activity = Activity(type: .gym, startDate: now)
        context.insert(activity)
        try? context.save()
        return GymSessionModel(activity: activity, context: context, notifier: notifier, restDuration: restDuration)
    }

    /// Starts a workout with the exercises and number of sets of `past`,
    /// prefilled with its values and nothing marked done.
    static func repeating(
        _ past: Activity,
        in context: ModelContext,
        notifier: RestNotifying,
        restDuration: TimeInterval,
        now: Date = .now
    ) -> GymSessionModel {
        let model = start(in: context, notifier: notifier, restDuration: restDuration, now: now)
        for pastEntry in past.sortedExercises {
            guard let exercise = pastEntry.exercise else { continue }
            let entry = model.appendEntry(for: exercise)
            let session = pastEntry.session
            for index in session.sets.indices {
                entry.sets.append(ExerciseSet(order: index, values: SetPrefill.repeated(from: session, index: index)))
            }
        }
        model.save()
        return model
    }

    var entries: [WorkoutExercise] { activity.sortedExercises }

    var hasUnfinishedSets: Bool {
        activity.exercises.contains { $0.sets.contains { !$0.isDone } }
    }

    var hasCompletedSets: Bool { activity.completedSetCount > 0 }

    // MARK: Exercises

    func addExercise(_ exercise: Exercise) {
        let entry = appendEntry(for: exercise)
        addSet(to: entry)
    }

    func removeExercise(_ entry: WorkoutExercise) {
        activity.exercises.removeAll { $0.id == entry.id }
        context.delete(entry)
        renumber(entries)
        save()
    }

    func moveExercises(from source: IndexSet, to destination: Int) {
        var ordered = entries
        ordered.move(fromOffsets: source, toOffset: destination)
        renumber(ordered)
        save()
    }

    func lastTime(for entry: WorkoutExercise) -> LastTimeSummary? {
        entry.exercise?.lastSession(excluding: activity).flatMap(LastTimeSummary.init(session:))
    }

    // MARK: Sets

    func addSet(to entry: WorkoutExercise) {
        let previous = entry.sortedSets.last?.values
        let lastSession = entry.exercise?.lastSession(excluding: activity)
        let values = SetPrefill.values(previousInSession: previous, lastSession: lastSession)
        entry.sets.append(ExerciseSet(order: entry.sets.count, values: values))
        save()
    }

    func removeSet(_ set: ExerciseSet, from entry: WorkoutExercise) {
        entry.sets.removeAll { $0.id == set.id }
        context.delete(set)
        for (index, set) in entry.sortedSets.enumerated() { set.order = index }
        save()
    }

    func toggleDone(_ set: ExerciseSet, now: Date = .now) {
        set.isDone.toggle()
        set.completedAt = set.isDone ? now : nil
        if set.isDone {
            startRest(now: now)
        }
        save()
    }

    // MARK: Rest timer

    func startRest(now: Date = .now) {
        let timer = RestTimer(duration: restDuration, startingAt: now)
        restTimer = timer
        notifier.scheduleRestEnd(at: timer.endDate)
    }

    func extendRest(by seconds: TimeInterval = 30, now: Date = .now) {
        guard var timer = restTimer else { return }
        timer.extend(by: seconds, now: now)
        restTimer = timer
        notifier.cancelRestEnd()
        notifier.scheduleRestEnd(at: timer.endDate)
    }

    func skipRest() {
        restTimer = nil
        notifier.cancelRestEnd()
    }

    // MARK: Lifecycle

    /// Drops sets not marked done (and exercises left empty), then saves the workout.
    func finish(now: Date = .now) {
        for entry in activity.exercises {
            for set in entry.sets where !set.isDone {
                entry.sets.removeAll { $0.id == set.id }
                context.delete(set)
            }
            if entry.sets.isEmpty {
                activity.exercises.removeAll { $0.id == entry.id }
                context.delete(entry)
            }
        }
        renumber(entries)
        for entry in activity.exercises {
            for (index, set) in entry.sortedSets.enumerated() { set.order = index }
        }

        let duration = max(0, now.timeIntervalSince(activity.startDate))
        activity.endDate = now
        activity.elapsedSeconds = duration
        activity.movingSeconds = duration
        activity.isFinished = true
        skipRest()
        save()
        summary = WorkoutSummary(duration: duration, setCount: activity.completedSetCount, volumeKg: activity.totalVolumeKg)
    }

    func discard() {
        skipRest()
        context.delete(activity)
        save()
    }

    func save() {
        try? context.save()
    }

    // MARK: Private

    @discardableResult
    private func appendEntry(for exercise: Exercise) -> WorkoutExercise {
        let entry = WorkoutExercise(exercise: exercise, order: activity.exercises.count)
        activity.exercises.append(entry)
        return entry
    }

    private func renumber(_ ordered: [WorkoutExercise]) {
        for (index, entry) in ordered.enumerated() { entry.order = index }
    }
}

extension ExerciseSet {
    convenience init(order: Int, values: SetValues) {
        self.init(order: order, weightKg: values.weightKg, reps: values.reps, durationSeconds: values.durationSeconds)
    }
}
