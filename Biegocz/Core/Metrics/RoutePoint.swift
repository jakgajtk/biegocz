import Foundation

/// One GPS fix. Pure value type so metrics code never depends on CoreLocation.
struct RoutePoint: Equatable, Codable, Sendable {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var timestamp: Date
    /// Horizontal accuracy in meters. Negative means the fix is invalid.
    var horizontalAccuracy: Double
}
