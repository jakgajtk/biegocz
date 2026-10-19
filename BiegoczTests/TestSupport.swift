import Foundation
@testable import Biegocz

enum TestSupport {
    static let polish = Locale(identifier: "pl_PL")
    static let english = Locale(identifier: "en_US")

    /// The app's localized resources for one language, independent of the simulator's language.
    static func bundle(for language: String) -> Bundle {
        let appBundle = Bundle(for: AppDependencies.self)
        guard let path = appBundle.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { fatalError("Missing \(language).lproj in the app bundle") }
        return bundle
    }

    /// Measurement formatting uses a no-break space before the unit.
    static func normalizingSpaces(_ string: String) -> String {
        string.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
    }
}
