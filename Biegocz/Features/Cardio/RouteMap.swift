import CoreLocation
import MapKit
import SwiftUI

/// The route as polylines, one per segment, with an optional pulsing position marker.
struct RouteMap: View {
    let segments: [[RoutePoint]]
    var current: RoutePoint?
    /// Keeps the camera on `current` (live screen); otherwise frames the whole route.
    var followsCurrent = false
    var tint: Color = .accentColor

    @State private var position = MapCameraPosition.automatic

    var body: some View {
        Map(position: $position) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                if segment.count > 1 {
                    MapPolyline(coordinates: segment.map(\.coordinate))
                        .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                }
            }
            if !followsCurrent, let start = segments.first?.first {
                Annotation(coordinate: start.coordinate) {
                    RouteEndpoint(systemImage: "flag.fill", tint: .success)
                } label: {
                    EmptyView()
                }
            }
            if !followsCurrent, let end = segments.last?.last {
                Annotation(coordinate: end.coordinate) {
                    RouteEndpoint(systemImage: "flag.checkered", tint: .danger)
                } label: {
                    EmptyView()
                }
            }
            if let current {
                Annotation(coordinate: current.coordinate) {
                    PulsingDot(tint: tint)
                } label: {
                    EmptyView()
                }
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {}
        .onChange(of: current) { _, point in
            guard followsCurrent, let point else { return }
            withAnimation(.easeInOut(duration: 0.8)) {
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

/// Current position: a solid dot with a soft ring breathing out of it.
private struct PulsingDot: View {
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .fill(tint.opacity(0.3))
                    .frame(width: 44, height: 44)
                    .scaleEffect(pulse ? 1 : 0.4)
                    .opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)
            }
            Circle()
                .fill(tint)
                .stroke(.white, lineWidth: 3)
                .frame(width: 18, height: 18)
                .shadow(color: .black.opacity(0.25), radius: 3)
        }
        .onAppear { pulse = true }
    }
}

private struct RouteEndpoint: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(tint, in: .circle)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 3)
    }
}

extension RoutePoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
