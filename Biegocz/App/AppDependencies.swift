import Foundation

/// Services the app talks to. Simulator builds get fakes, because HealthKit
/// doesn't work there and GPX replay is the only way to test live tracking.
@MainActor
@Observable
final class AppDependencies {
    let location: any LocationProvider
    let health: any HealthStore
    let altitude: any AltitudeProvider
    /// Apple Maps directions also work in the simulator, so there's no fake.
    let directions: any DirectionsProvider

    init(
        location: any LocationProvider,
        health: any HealthStore,
        altitude: any AltitudeProvider,
        directions: any DirectionsProvider = MapKitDirections()
    ) {
        self.location = location
        self.health = health
        self.altitude = altitude
        self.directions = directions
    }

    static func live() -> AppDependencies {
        #if targetEnvironment(simulator)
        AppDependencies(location: GPXReplayLocationProvider(), health: NoOpHealthStore(), altitude: NoAltitudeProvider())
        #else
        AppDependencies(location: CoreLocationProvider(), health: HealthKitStore(), altitude: BarometerAltitudeProvider())
        #endif
    }
}
