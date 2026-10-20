import SwiftUI

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

    static let appearanceKey = "settings.appearance"
    static let languageKey = "settings.language"

    static func autoPause(for type: ActivityType, defaults: UserDefaults = .standard) -> Bool {
        switch type {
        case .run: defaults.object(forKey: autoPauseRunKey) as? Bool ?? defaultAutoPauseRun
        case .ride: defaults.object(forKey: autoPauseRideKey) as? Bool ?? defaultAutoPauseRide
        case .gym: false
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// The app's language. Stored as the app's own `AppleLanguages` preference,
/// the same one iOS sets under Settings › Biegocz › Language, so it applies
/// the next time the app starts.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english = "en", polish = "pl"

    var id: Self { self }

    /// Language names are shown in their own language, as iOS does.
    var title: Text {
        switch self {
        case .system: Text("Device language")
        case .english: Text(verbatim: "English")
        case .polish: Text(verbatim: "Polski")
        }
    }

    static let appleLanguagesKey = "AppleLanguages"

    func apply(to defaults: UserDefaults = .standard) {
        if self == .system {
            defaults.removeObject(forKey: Self.appleLanguagesKey)
        } else {
            defaults.set([rawValue], forKey: Self.appleLanguagesKey)
        }
    }

    /// The language the app is showing right now.
    static var current: AppLanguage {
        AppLanguage(rawValue: Bundle.main.preferredLocalizations.first ?? "") ?? .english
    }
}
