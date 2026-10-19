import Foundation

/// Services the app talks to. Simulator builds get fakes, because HealthKit
/// doesn't work there and GPX replay is the only way to test live tracking.
@MainActor
@Observable
final class AppDependencies {
    let location: any LocationProvider
    let health: any HealthStore

    init(location: any LocationProvider, health: any HealthStore) {
        self.location = location
        self.health = health
    }

    static func live() -> AppDependencies {
        #if targetEnvironment(simulator)
        AppDependencies(location: GPXReplayLocationProvider(), health: NoOpHealthStore())
        #else
        AppDependencies(location: CoreLocationProvider(), health: HealthKitStore())
        #endif
    }
}
