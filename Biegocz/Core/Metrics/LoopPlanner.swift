import Foundation

/// A latitude/longitude pair without CoreLocation, for pure route math.
struct Coordinate: Equatable, Hashable, Codable, Sendable {
    var latitude: Double
    var longitude: Double
}

extension GeoMath {
    static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        distance(
            RoutePoint(latitude: a.latitude, longitude: a.longitude, altitude: 0, timestamp: .distantPast, horizontalAccuracy: 0),
            RoutePoint(latitude: b.latitude, longitude: b.longitude, altitude: 0, timestamp: .distantPast, horizontalAccuracy: 0)
        )
    }

    /// The point `meters` away from `start` heading `bearing` degrees (0 = north, clockwise).
    static func destination(from start: Coordinate, bearing: Double, meters: Double) -> Coordinate {
        let angular = meters / earthRadius
        let heading = bearing * .pi / 180
        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(heading))
        let lon2 = lon1 + atan2(sin(heading) * sin(angular) * cos(lat1), cos(angular) - sin(lat1) * sin(lat2))
        return Coordinate(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    static func length(of path: [Coordinate]) -> Double {
        zip(path, path.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }
}

/// Plans round trips of a target length: waypoints on a circle that passes
/// through the start, in a given direction. Roads are never straight, so the
/// directions service's real length is fed back to resize the circle.
enum LoopPlanner {
    /// Typical road length per meter of straight line; the first guess.
    static let detourFactor = 1.3
    /// Close enough to the target (fraction of it).
    static let tolerance = 0.1
    /// Attempts per route, the first one included.
    static let maxAttempts = 3
    /// Waypoints besides the start. Three gives a rounded loop with few requests.
    static let waypointCount = 3

    /// Radius of the circle for a loop of `distance` meters of road.
    static func initialRadius(for distance: Double) -> Double {
        // Straight-line perimeter of the waypoint polygon inscribed in a circle of radius 1.
        let sides = Double(waypointCount + 1)
        let perimeter = sides * 2 * sin(.pi / sides)
        return distance / (perimeter * detourFactor)
    }

    /// The loop's stops in order: start, waypoints, start. The circle's
    /// centre lies `radius` from the start towards `bearing`.
    static func waypoints(from start: Coordinate, bearing: Double, radius: Double) -> [Coordinate] {
        let center = GeoMath.destination(from: start, bearing: bearing, meters: radius)
        let sides = waypointCount + 1
        let stops = (1...waypointCount).map { index in
            // Walk around the circle from the start, which sits at bearing + 180° seen from the centre.
            let angle = bearing + 180 + Double(index) * 360 / Double(sides)
            return GeoMath.destination(from: center, bearing: angle, meters: radius)
        }
        return [start] + stops + [start]
    }

    /// The next radius after a route of `actual` meters came back for `target`.
    static func adjustedRadius(_ radius: Double, target: Double, actual: Double) -> Double {
        guard actual > 0 else { return radius }
        return radius * min(max(target / actual, 0.5), 2)
    }

    static func isCloseEnough(_ actual: Double, to target: Double) -> Bool {
        abs(actual - target) <= target * tolerance
    }

    /// Directions for suggestions: evenly spread, starting from `offset`.
    static func bearings(count: Int, offset: Double) -> [Double] {
        (0..<count).map { (offset + Double($0) * 360 / Double(count)).truncatingRemainder(dividingBy: 360) }
    }
}
