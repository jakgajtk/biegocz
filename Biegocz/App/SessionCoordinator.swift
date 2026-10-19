import Foundation
import SwiftData

/// Owns the live session (at most one at a time) and decides what to do with
/// sessions left unfinished by a crash or a force-quit.
@MainActor
@Observable
final class SessionCoordinator {
    var gymSession: GymSessionModel?
    /// An unfinished activity found on launch, waiting for Resume / Save / Discard.
    var recoverable: Activity?

    private let restNotifier: RestNotifying

    init(restNotifier: RestNotifying) {
        self.restNotifier = restNotifier
    }

    var hasActiveSession: Bool { gymSession != nil }

    private var restDuration: TimeInterval {
        let stored = UserDefaults.standard.integer(forKey: AppSettings.restDurationKey)
        return TimeInterval(stored > 0 ? stored : AppSettings.defaultRestDuration)
    }

    // MARK: Gym

    func startGym(in context: ModelContext) {
        guard !hasActiveSession else { return }
        gymSession = .start(in: context, notifier: restNotifier, restDuration: restDuration)
    }

    func repeatGym(_ past: Activity, in context: ModelContext) {
        guard !hasActiveSession else { return }
        gymSession = .repeating(past, in: context, notifier: restNotifier, restDuration: restDuration)
    }

    func closeGym() {
        gymSession = nil
    }

    // MARK: Recovery

    func findRecoverable(in context: ModelContext) {
        guard !hasActiveSession, recoverable == nil else { return }
        let descriptor = FetchDescriptor<Activity>(
            predicate: #Predicate { !$0.isFinished },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        guard let unfinished = try? context.fetch(descriptor) else { return }
        for activity in unfinished where activity.type == .gym && activity.exercises.isEmpty {
            // Nothing logged yet: nothing worth asking about.
            context.delete(activity)
        }
        try? context.save()
        recoverable = unfinished.first { !$0.isDeleted && !($0.type == .gym && $0.exercises.isEmpty) }
    }

    func resumeRecoverable(in context: ModelContext) {
        guard let activity = recoverable else { return }
        recoverable = nil
        switch activity.type {
        case .gym:
            gymSession = GymSessionModel(activity: activity, context: context, notifier: restNotifier, restDuration: restDuration)
        case .run, .ride:
            break
        }
    }

    func saveRecoverable(in context: ModelContext) {
        guard let activity = recoverable else { return }
        recoverable = nil
        switch activity.type {
        case .gym:
            let model = GymSessionModel(activity: activity, context: context, notifier: restNotifier, restDuration: restDuration)
            // End at the last completed set rather than now, which may be hours later.
            let lastSet = activity.exercises.flatMap(\.sets).compactMap(\.completedAt).max()
            model.finish(now: lastSet ?? activity.startDate)
        case .run, .ride:
            break
        }
    }

    func discardRecoverable(in context: ModelContext) {
        guard let activity = recoverable else { return }
        recoverable = nil
        context.delete(activity)
        try? context.save()
    }
}
