import Foundation

/// Access to Apple Health. The app must keep working when this is
/// unavailable or access is denied. Workout saving arrives in Phase 4.
@MainActor
protocol HealthStore: AnyObject {
    var isAvailable: Bool { get }

    /// Asks for access the first time it's needed. Denial is not an error.
    func requestAuthorization() async throws
}

/// Used in the simulator, where HealthKit is unavailable.
@MainActor
final class NoOpHealthStore: HealthStore {
    var isAvailable: Bool { false }

    func requestAuthorization() async throws {}
}
