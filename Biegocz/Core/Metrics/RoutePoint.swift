import Foundation

/// One GPS fix. Pure value type so metrics code never depends on CoreLocation.
struct RoutePoint: Equatable, Codable, Sendable {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var timestamp: Date
    /// Horizontal accuracy in meters. Negative means the fix is invalid.
    var horizontalAccuracy: Double

    /// Coordinates on the globe and a finite altitude. Imported files can
    /// contain anything, including `nan`.
    var hasValidCoordinates: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude) && altitude.isFinite
    }
}
