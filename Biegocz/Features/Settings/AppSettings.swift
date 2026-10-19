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
}
