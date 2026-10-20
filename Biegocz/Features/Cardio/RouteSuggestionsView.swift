import MapKit
import SwiftUI

/// Pick a distance, get three loops around you, choose one.
struct RouteSuggestionsView: View {
    @State var model: RouteSuggestionsModel
    let onChoose: (SuggestedRoute) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var position = MapCameraPosition.automatic

    private var tint: Color { model.type.tint }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                map
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.clear, .appBackground], startPoint: .top, endPoint: .bottom)
                            .frame(height: 32)
                            .allowsHitTesting(false)
                    }
                panel
            }
            .appBackground()
            .navigationTitle("Suggested routes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Haptics.tap()
                        model.shuffle()
                    } label: {
                        Label("Other directions", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(model.isLoading)
                }
            }
        }
        .task {
            if model.routes.isEmpty { model.load() }
        }
        .onDisappear { model.cancel() }
        .onChange(of: model.routes.count) {
            withAnimation(Design.spring) { position = .automatic }
        }
        .sensoryFeedback(.selection, trigger: model.selectedID)
    }

    private var map: some View {
        Map(position: $position) {
            ForEach(model.routes) { route in
                let isSelected = route.id == model.selectedID
                MapPolyline(coordinates: route.coordinates.map(\.clCoordinate))
                    .stroke(
                        isSelected ? tint : Color.secondary.opacity(0.55),
                        style: StrokeStyle(lineWidth: isSelected ? 6 : 4, lineCap: .round, lineJoin: .round)
                    )
            }
            // Drawn again on top so the selected loop is never hidden.
            if let selected = model.selected {
                MapPolyline(coordinates: selected.coordinates.map(\.clCoordinate))
                    .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            Annotation(coordinate: model.start.clCoordinate) {
                Image(systemName: model.type.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint, in: .circle)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.2), radius: 3)
            } label: {
                EmptyView()
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {}
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 16) {
            DistanceChips(
                presets: RouteSuggestionsModel.presets(for: model.type),
                selectedMeters: model.targetDistance,
                tint: tint
            ) { meters in
                Haptics.selection()
                model.setTarget(meters)
            }

            routeList

            Button {
                guard let route = model.selected else { return }
                Haptics.success()
                onChoose(route)
                dismiss()
            } label: {
                Label("Use this route", systemImage: "checkmark")
            }
            .buttonStyle(.prominent(tint, height: 60))
            .disabled(model.selected == nil)
            .opacity(model.selected == nil ? 0.5 : 1)
        }
        .padding()
        .background(Color.appBackground)
        .animation(Design.spring, value: model.routes)
        .animation(Design.spring, value: model.isLoading)
        .animation(Design.spring, value: model.isThrottled)
    }

    @ViewBuilder
    private var routeList: some View {
        if model.failed {
            VStack(spacing: 8) {
                Text("No routes found nearby")
                    .font(.headline)
                Text("Check your internet connection, or try another distance.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try again") { model.load() }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .card()
        } else {
            VStack(spacing: 10) {
                if model.isThrottled {
                    Label {
                        Text(model.isLoading ? "Apple Maps needs a short break. Trying again in a moment…" : "Apple Maps needs a short break, so there are fewer routes. Try this distance again in a minute.")
                    } icon: {
                        Image(systemName: "hourglass")
                            .symbolEffect(.pulse, isActive: model.isLoading)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                }
                ForEach(model.routes) { route in
                    RouteRow(route: route, isSelected: route.id == model.selectedID, tint: tint) {
                        model.selectedID = route.id
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if model.isLoading {
                    ForEach(model.routes.count..<RouteSuggestionsModel.count, id: \.self) { _ in
                        LoadingRow()
                    }
                }
            }
        }
    }
}

private struct DistanceChips: View {
    let presets: [Double]
    let selectedMeters: Double
    let tint: Color
    let onSelect: (Double) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { kilometers in
                    let meters = kilometers * 1000
                    let isSelected = abs(meters - selectedMeters) < 1
                    Button {
                        onSelect(meters)
                    } label: {
                        Text(verbatim: Formatters.distance(meters: meters, fractionDigits: kilometers.rounded() == kilometers ? 0 : 1))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 14)
                            .frame(minHeight: 40)
                            .foregroundStyle(isSelected ? .white : .primary)
                            .background(isSelected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(.cardBackground), in: .capsule)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct RouteRow: View {
    let route: SuggestedRoute
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "location.north.fill")
                    .font(.headline)
                    .rotationEffect(.degrees(route.bearing))
                    .foregroundStyle(isSelected ? .white : tint)
                    .frame(width: 40, height: 40)
                    .background(isSelected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.15)), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Compass.heading(route.bearing))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Loop")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(verbatim: Formatters.distance(meters: route.distance))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .padding(12)
            .background(.cardBackground, in: .rect(cornerRadius: Design.smallCornerRadius + 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Design.smallCornerRadius + 4, style: .continuous)
                    .stroke(isSelected ? tint : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct LoadingRow: View {
    var body: some View {
        HStack(spacing: 14) {
            ProgressView()
                .frame(width: 40, height: 40)
            Text("Finding a route…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(.cardBackground, in: .rect(cornerRadius: Design.smallCornerRadius + 4, style: .continuous))
    }
}

/// "Heads north" and so on, for the direction a loop goes out in.
enum Compass {
    static func heading(_ bearing: Double) -> LocalizedStringKey {
        let normalized = (bearing.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        switch Int((normalized + 22.5) / 45) % 8 {
        case 0: return "Heads north"
        case 1: return "Heads northeast"
        case 2: return "Heads east"
        case 3: return "Heads southeast"
        case 4: return "Heads south"
        case 5: return "Heads southwest"
        case 6: return "Heads west"
        default: return "Heads northwest"
        }
    }
}
