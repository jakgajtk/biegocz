import CoreLocation

@MainActor
final class CoreLocationProvider: NSObject, LocationProvider {
    private let manager = CLLocationManager()
    private var authorizationWaiters: [CheckedContinuation<LocationAuthorization, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
    }

    var authorization: LocationAuthorization {
        Self.map(manager.authorizationStatus)
    }

    func requestAuthorization() async -> LocationAuthorization {
        guard manager.authorizationStatus == .notDetermined else { return authorization }
        return await withCheckedContinuation { continuation in
            authorizationWaiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationUpdates(for activity: ActivityType) -> AsyncStream<RoutePoint> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                // Keeps updates flowing while the screen is locked (When In Use + background mode).
                let backgroundSession = CLBackgroundActivitySession()
                defer { backgroundSession.invalidate() }
                do {
                    for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                        if let location = update.location {
                            continuation.yield(RoutePoint(location))
                        }
                    }
                } catch {
                    // Cancellation or a terminal location error ends the stream.
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func authorizationDidChange() {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        let waiters = authorizationWaiters
        authorizationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: Self.map(status))
        }
    }

    private static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .authorizedWhenInUse, .authorizedAlways: .authorized
        default: .denied
        }
    }
}

extension CoreLocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationDidChange()
        }
    }
}

extension RoutePoint {
    init(_ location: CLLocation) {
        self.init(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            timestamp: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy
        )
    }
}
