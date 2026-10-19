import Foundation

enum LocationAuthorization: Sendable {
    case notDetermined
    case denied
    case authorized
}

/// Source of GPS fixes. The app uses `CoreLocationProvider` on device and
/// `GPXReplayLocationProvider` in the simulator.
@MainActor
protocol LocationProvider: AnyObject {
    var authorization: LocationAuthorization { get }

    /// Asks for When In Use access if not decided yet, and returns the result.
    func requestAuthorization() async -> LocationAuthorization

    /// Raw, unfiltered fixes. Tracking keeps running with the screen locked
    /// until the consuming task is cancelled.
    func locationUpdates(for activity: ActivityType) -> AsyncStream<RoutePoint>
}
