import Foundation
import SwiftData

/// Owns the live session (at most one at a time) and decides what to do with
/// sessions left unfinished by a crash or a force-quit.
@MainActor
@Observable
final class SessionCoordinator {
    var gymSession: GymSessionModel?
    /// Pre-start screen of a run or ride.
    var cardioSetup: PreStartModel?
    var cardioSession: CardioSessionModel?
    /// An unfinished activity found on launch, waiting for Resume / Save / Discard.
    var recoverable: Activity?

    private let restNotifier: RestNotifying
    private let location: any LocationProvider
    private let health: any HealthStore
    private let altitude: any AltitudeProvider

    init(
        restNotifier: RestNotifying,
        location: any LocationProvider,
        health: any HealthStore,
        altitude: any AltitudeProvider = NoAltitudeProvider()
    ) {
        self.restNotifier = restNotifier
        self.location = location
        self.health = health
        self.altitude = altitude
    }

    var hasActiveSession: Bool {
        gymSession != nil || cardioSetup != nil || cardioSession != nil
    }

    private var restDuration: TimeInterval {
        let stored = UserDefaults.standard.integer(forKey: AppSettings.restDurationKey)
        return TimeInterval(stored > 0 ? stored : AppSettings.defaultRestDuration)
    }

    // MARK: Gym

    func startGym(in context: ModelContext) {
        guard !hasActiveSession else { return }
        gymSession = makeGym(.start(in: context, notifier: restNotifier, restDuration: restDuration))
    }

    func repeatGym(_ past: Activity, in context: ModelContext) {
        guard !hasActiveSession else { return }
        gymSession = makeGym(.repeating(past, in: context, notifier: restNotifier, restDuration: restDuration))
    }

    func closeGym() {
        gymSession = nil
    }

    private func makeGym(_ model: GymSessionModel) -> GymSessionModel {
        model.health = health
        return model
    }

    // MARK: Run and ride

    func prepareCardio(_ type: ActivityType) {
        guard !hasActiveSession else { return }
        cardioSetup = PreStartModel(type: type, location: location, health: health)
    }

    func startCardio(in context: ModelContext) {
        guard let setup = cardioSetup else { return }
        setup.stop()
        let session = CardioSessionModel.start(
            setup.type,
            in: context,
            location: location,
            health: health,
            autoPause: AppSettings.autoPause(for: setup.type)
        )
        session.altitude = altitude
        session.plannedRoute = setup.plannedRoute?.coordinates ?? []
        session.startTracking()
        cardioSession = session
        cardioSetup = nil
    }

    func cancelCardioSetup() {
        cardioSetup?.stop()
        cardioSetup = nil
    }

    func closeCardio() {
        cardioSession?.stopTracking()
        cardioSession = nil
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
            gymSession = makeGym(GymSessionModel(
                activity: activity, context: context, notifier: restNotifier, restDuration: restDuration
            ))
        case .run, .ride:
            endAbandonedHealthSession()
            let session = CardioSessionModel.recover(activity, in: context, location: location, health: health)
            session.altitude = altitude
            session.startTracking()
            cardioSession = session
        }
    }

    func saveRecoverable(in context: ModelContext) {
        guard let activity = recoverable else { return }
        recoverable = nil
        switch activity.type {
        case .gym:
            let model = makeGym(GymSessionModel(
                activity: activity, context: context, notifier: restNotifier, restDuration: restDuration
            ))
            // End at the last completed set rather than now, which may be hours later.
            let lastSet = activity.exercises.flatMap(\.sets).compactMap(\.completedAt).max()
            model.finish(now: lastSet ?? activity.startDate)
        case .run, .ride:
            endAbandonedHealthSession()
            let session = CardioSessionModel.recover(activity, in: context, location: location, health: health)
            // End at the last snapshot taken before the app stopped.
            session.finish(at: session.engine.savedAt ?? activity.startDate)
        }
    }

    func discardRecoverable(in context: ModelContext) {
        guard let activity = recoverable else { return }
        recoverable = nil
        if activity.type.isCardio {
            endAbandonedHealthSession()
        }
        context.delete(activity)
        try? context.save()
    }

    /// A Health session from before a crash can't be continued reliably; end it.
    /// The recovered activity is saved to Health from our own data when finished.
    private func endAbandonedHealthSession() {
        Task { [health] in await health.endAbandonedLiveWorkout() }
    }
}
