import Foundation

/// What gets saved to Health for one finished activity.
struct WorkoutRecord: Sendable {
    var type: ActivityType
    var start: Date
    var end: Date
    /// Route split at pauses; empty for gym workouts.
    var segments: [[RoutePoint]] = []
}

enum HealthError: Error {
    case unavailable
    case notAuthorized
}

/// Access to Apple Health. The app must keep working when this is
/// unavailable or access is denied: every caller treats failure as "not saved".
@MainActor
protocol HealthStore: AnyObject {
    var isAvailable: Bool { get }

    /// Whether the app may save workouts. `false` until the user allows it.
    var canSaveWorkouts: Bool { get }

    /// Asks for access the first time it's needed; later calls return at once.
    func requestAuthorization() async

    /// Starts a live workout session for a run or ride, or `nil` without access.
    func startLiveWorkout(_ type: ActivityType, at start: Date) async -> (any LiveWorkout)?

    /// Saves a finished activity without a live session (gym workouts, and runs
    /// or rides recovered after a crash). Returns the Health workout's UUID.
    func saveWorkout(_ record: WorkoutRecord) async throws -> UUID

    /// Ends a live session left running by a crash, so it doesn't linger.
    func endAbandonedLiveWorkout() async
}

/// A run or ride being recorded in Health while it happens.
@MainActor
protocol LiveWorkout: AnyObject {
    func pause(at date: Date)
    func resume(at date: Date)
    /// Adds distance and route, ends the session and returns the workout's UUID.
    func finish(_ record: WorkoutRecord) async throws -> UUID
    func discard()
}

/// Used in the simulator, where HealthKit is unavailable.
@MainActor
final class NoOpHealthStore: HealthStore {
    var isAvailable: Bool { false }
    var canSaveWorkouts: Bool { false }

    func requestAuthorization() async {}

    func startLiveWorkout(_ type: ActivityType, at start: Date) async -> (any LiveWorkout)? { nil }

    func saveWorkout(_ record: WorkoutRecord) async throws -> UUID {
        throw HealthError.unavailable
    }

    func endAbandonedLiveWorkout() async {}
}
