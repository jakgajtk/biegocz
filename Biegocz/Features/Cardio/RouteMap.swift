import CoreLocation
import MapKit
import SwiftUI

/// The route as polylines, one per segment, with an optional position marker.
struct RouteMap: View {
    let segments: [[RoutePoint]]
    var current: RoutePoint?
    /// Keeps the camera on `current` (live screen); otherwise frames the whole route.
    var followsCurrent = false

    @State private var position = MapCameraPosition.automatic

    var body: some View {
        Map(position: $position) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                if segment.count > 1 {
                    MapPolyline(coordinates: segment.map(\.coordinate))
                        .stroke(.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
            if let current {
                Annotation(coordinate: current.coordinate) {
                    Circle()
                        .fill(.blue)
                        .stroke(.white, lineWidth: 3)
                        .frame(width: 18, height: 18)
                        .shadow(radius: 2)
                } label: {
                    EmptyView()
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .onChange(of: current) { _, point in
            guard followsCurrent, let point else { return }
            withAnimation {
                position = .camera(MapCamera(centerCoordinate: point.coordinate, distance: 900))
            }
        }
        .onAppear {
            if followsCurrent, let current {
                position = .camera(MapCamera(centerCoordinate: current.coordinate, distance: 900))
            }
        }
    }
}

extension RoutePoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
