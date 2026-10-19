import Foundation
import Testing
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

    /// Points of a bundled sample route, with their original timestamps.
    static func sampleRoute(_ name: String) throws -> [RoutePoint] {
        let url = try #require(Bundle(for: AppDependencies.self).url(forResource: name, withExtension: "gpx"))
        return try GPXParser.parse(Data(contentsOf: url))
    }

    /// A straight line heading north at `speed` m/s, one fix per second.
    static func straightLine(seconds: Int, speed: Double, start: Date, accuracy: Double = 5) -> [RoutePoint] {
        (0...seconds).map { second in
            RoutePoint(
                latitude: 52.2 + Double(second) * speed / 111_195,
                longitude: 21.0,
                altitude: 100,
                timestamp: start.addingTimeInterval(Double(second)),
                horizontalAccuracy: accuracy
            )
        }
    }
}

/// A location provider that never emits; tests feed points directly.
@MainActor
final class SilentLocationProvider: LocationProvider {
    var authorization: LocationAuthorization { .authorized }
    func requestAuthorization() async -> LocationAuthorization { .authorized }
    func locationUpdates(for activity: ActivityType) -> AsyncStream<RoutePoint> {
        AsyncStream { $0.finish() }
    }
}
