import CoreLocation
import MapKit

/// One leg of a planned route, along roads or paths.
struct DirectionsLeg: Equatable, Sendable {
    var coordinates: [Coordinate]
    var distance: Double
}

/// Road directions between two points: Apple Maps on device, a fake in tests.
protocol DirectionsProvider: Sendable {
    /// Throws `DirectionsError.throttled` when the service refuses more requests for now.
    func leg(from start: Coordinate, to end: Coordinate, for activity: ActivityType) async throws -> DirectionsLeg
}

enum DirectionsError: Error, Equatable {
    /// Apple Maps allows about 50 direction requests a minute per app, then
    /// refuses them for a while. Retrying right away only makes it longer.
    case throttled
}

/// Apple Maps directions: walking for runs, cycling for rides. Cycling
/// directions aren't available everywhere; walking is the fallback there.
struct MapKitDirections: DirectionsProvider {
    func leg(from start: Coordinate, to end: Coordinate, for activity: ActivityType) async throws -> DirectionsLeg {
        do {
            if activity == .ride {
                do {
                    return try await leg(from: start, to: end, transport: .cycling)
                } catch where !Self.isThrottled(error) {
                    // No cycling directions here: fall back to walking.
                }
            }
            return try await leg(from: start, to: end, transport: .walking)
        } catch where Self.isThrottled(error) {
            throw DirectionsError.throttled
        }
    }

    /// When throttled, MapKit reports `loadingThrottled` either as the error
    /// code or, wrapped in an "unknown" error, under `MKDirectionsErrorCode`.
    static func isThrottled(_ error: Error) -> Bool {
        let error = error as NSError
        guard error.domain == MKError.errorDomain else { return false }
        let throttled = MKError.Code.loadingThrottled.rawValue
        return error.code == throttled || (error.userInfo["MKDirectionsErrorCode"] as? Int) == Int(throttled)
    }

    private func leg(from start: Coordinate, to end: Coordinate, transport: MKDirectionsTransportType) async throws -> DirectionsLeg {
        let request = MKDirections.Request()
        request.source = mapItem(start)
        request.destination = mapItem(end)
        request.transportType = transport
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw MKError(.directionsNotFound) }
        var points = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: route.polyline.pointCount)
        route.polyline.getCoordinates(&points, range: NSRange(location: 0, length: points.count))
        return DirectionsLeg(
            coordinates: points.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) },
            distance: route.distance
        )
    }

    private func mapItem(_ coordinate: Coordinate) -> MKMapItem {
        MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
    }
}
