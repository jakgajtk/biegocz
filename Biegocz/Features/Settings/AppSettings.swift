import Foundation

/// UserDefaults keys and defaults, used with `@AppStorage`.
enum AppSettings {
    static let weightStepKey = "settings.weightStepKg"
    static let defaultWeightStep = 2.5
    static let weightStepOptions: [Double] = [1, 1.25, 2, 2.5, 5]

    static let restDurationKey = "settings.restDurationSeconds"
    static let defaultRestDuration = 120
    static let restDurationRange = 30...600
    static let restDurationStep = 15

    static let autoPauseRunKey = "settings.autoPauseRun"
    static let autoPauseRideKey = "settings.autoPauseRide"
    static let defaultAutoPauseRun = false
    static let defaultAutoPauseRide = true

    static func autoPause(for type: ActivityType, defaults: UserDefaults = .standard) -> Bool {
        switch type {
        case .run: defaults.object(forKey: autoPauseRunKey) as? Bool ?? defaultAutoPauseRun
        case .ride: defaults.object(forKey: autoPauseRideKey) as? Bool ?? defaultAutoPauseRide
        case .gym: false
        }
    }
}
