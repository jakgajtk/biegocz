import CoreLocation
import MapKit

/// One leg of a planned route, along roads or paths.
struct DirectionsLeg: Equatable, Sendable {
    var coordinates: [Coordinate]
    var distance: Double
}

/// Road directions between two points: Apple Maps on device, a fake in tests.
protocol DirectionsProvider: Sendable {
    func leg(from start: Coordinate, to end: Coordinate, for activity: ActivityType) async throws -> DirectionsLeg
}

/// Apple Maps directions: walking for runs, cycling for rides. Cycling
/// directions aren't available everywhere; walking is the fallback there.
struct MapKitDirections: DirectionsProvider {
    func leg(from start: Coordinate, to end: Coordinate, for activity: ActivityType) async throws -> DirectionsLeg {
        if activity == .ride, let leg = try? await leg(from: start, to: end, transport: .cycling) {
            return leg
        }
        return try await leg(from: start, to: end, transport: .walking)
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
