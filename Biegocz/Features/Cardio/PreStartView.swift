import MapKit
import SwiftUI

struct PreStartView: View {
    let model: PreStartModel
    let onStart: () -> Void
    let onCancel: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppDependencies.self) private var dependencies
    @State private var routeSuggestions: RouteSuggestionsModel?
    @State private var isConfirmingWeakSignal = false
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    @State private var pulse = false

    private var tint: Color { model.type.tint }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 14) {
                    IconBadge(systemImage: model.type.systemImage, tint: tint, size: 84)
                    Text(model.type.title)
                        .font(.largeTitle.weight(.bold))
                }
                .appearEffect()

                if model.authorization == .denied {
                    VStack(spacing: 12) {
                        Text("Location access is off")
                            .font(.headline)
                        Text("Allow location access in Settings to record your route and distance.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                } else {
                    GPSQualityBadge(quality: model.quality)
                        .appearEffect(delay: 0.1)
                    routePlanning
                        .appearEffect(delay: 0.15)
                }

                Spacer()

                startButton
                    .appearEffect(delay: 0.2)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .appBackground()
            .overlay {
                if let countdown {
                    CountdownOverlay(value: countdown, tint: tint) {
                        finishCountdown()
                    }
                    .transition(.opacity)
                }
            }
            .animation(Design.spring, value: countdown)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        countdownTask?.cancel()
                        onCancel()
                    }
                }
            }
            .task {
                await model.start()
            }
            .onAppear { pulse = true }
            .onDisappear { countdownTask?.cancel() }
            .confirmationDialog(
                "GPS signal is weak",
                isPresented: $isConfirmingWeakSignal,
                titleVisibility: .visible
            ) {
                Button("Start anyway", action: beginCountdown)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Distance may be inaccurate until the signal improves.")
            }
        }
    }

    @ViewBuilder
    private var routePlanning: some View {
        Group {
            if let route = model.plannedRoute {
                PlannedRouteCard(route: route, tint: tint) {
                    showSuggestions()
                } onRemove: {
                    Haptics.tap()
                    model.plannedRoute = nil
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                Button(action: showSuggestions) {
                    Label {
                        Text(model.position == nil ? "Waiting for location…" : "Suggested routes")
                    } icon: {
                        Image(systemName: "point.topright.arrow.triangle.backward.to.point.bottomleft.scurvepath.fill")
                    }
                    .font(.headline)
                    .foregroundStyle(tint)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 48)
                    .background(tint.opacity(0.14), in: .capsule)
                }
                .buttonStyle(.pressable)
                .disabled(model.position == nil)
            }
        }
        .padding(.horizontal)
        .animation(Design.spring, value: model.plannedRoute)
        #if DEBUG
        .onChange(of: model.position != nil) { _, hasPosition in
            if hasPosition, DebugLaunch.screen == .routes, routeSuggestions == nil { showSuggestions() }
        }
        #endif
        .sheet(item: $routeSuggestions) { suggestions in
            RouteSuggestionsView(model: suggestions) { route in
                model.plannedRoute = route
            }
        }
    }

    private func showSuggestions() {
        guard let position = model.position else { return }
        Haptics.tap()
        routeSuggestions = RouteSuggestionsModel(
            type: model.type,
            start: position,
            directions: dependencies.directions,
            bearingOffset: Double.random(in: 0..<120)
        )
    }

    private var startButton: some View {
        Button {
            Haptics.firm()
            if model.quality == .poor || model.quality == .none {
                isConfirmingWeakSignal = true
            } else {
                beginCountdown()
            }
        } label: {
            ZStack {
                if !reduceMotion {
                    Circle()
                        .fill(tint.opacity(0.18))
                        .scaleEffect(pulse ? 1.18 : 1)
                        .opacity(pulse ? 0 : 1)
                        .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: pulse)
                }
                Circle()
                    .fill(tint.gradient)
                    .shadow(color: tint.opacity(0.4), radius: 20, y: 8)
                Text("Start")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 190, height: 190)
        }
        .buttonStyle(PressableStyle(scale: 0.93))
        .disabled(model.authorization != .authorized)
        .opacity(model.authorization == .authorized ? 1 : 0.4)
    }

    /// 3-2-1 with a buzz each second; tap to skip.
    private func beginCountdown() {
        guard countdownTask == nil else { return }
        if reduceMotion {
            onStart()
            return
        }
        countdownTask = Task {
            for value in [3, 2, 1] {
                countdown = value
                Haptics.firm()
                try? await Task.sleep(for: .milliseconds(800))
                if Task.isCancelled { return }
            }
            finishCountdown()
        }
    }

    private func finishCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
        Haptics.success()
        onStart()
    }
}

private struct PlannedRouteCard: View {
    let route: SuggestedRoute
    let tint: Color
    let onChange: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Map(initialPosition: .automatic, interactionModes: []) {
                MapPolyline(coordinates: route.coordinates.map(\.clCoordinate))
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
            .frame(height: 130)
            .allowsHitTesting(false)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: Formatters.distance(meters: route.distance))
                        .font(.headline)
                        .monospacedDigit()
                    Text(Compass.heading(route.bearing))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Change", action: onChange)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(Text("Remove route"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(.cardBackground)
        .clipShape(.rect(cornerRadius: Design.cornerRadius, style: .continuous))
    }
}

private struct CountdownOverlay: View {
    let value: Int
    let tint: Color
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 20) {
                Text(verbatim: value.formatted())
                    .font(.system(size: 160, weight: .heavy, design: .rounded))
                    .foregroundStyle(tint.gradient)
                    .contentTransition(.numericText(countsDown: true))
                    .id(value)
                    .transition(.scale(scale: 1.6).combined(with: .opacity))
                Text("Tap to skip")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: onSkip)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Tap to skip"))
    }
}

private struct GPSQualityBadge: View {
    let quality: GPSQuality

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: quality == .none ? "location.circle" : "location.fill")
                .foregroundStyle(color)
                .symbolEffect(.variableColor.iterative, isActive: quality == .none)
                .contentTransition(.symbolEffect(.replace))
            Text(label)
                .font(.headline)
                .contentTransition(.opacity)
            if quality != .none {
                SignalBars(level: level, tint: color)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.cardBackground, in: .capsule)
        .animation(Design.spring, value: quality)
        .accessibilityElement(children: .combine)
    }

    private var level: Int {
        switch quality {
        case .none: 0
        case .poor: 1
        case .ok: 2
        case .good: 3
        }
    }

    private var color: Color {
        switch quality {
        case .none: .secondary
        case .poor: .danger
        case .ok: .warning
        case .good: .success
        }
    }

    private var label: LocalizedStringKey {
        switch quality {
        case .none: "Searching for GPS…"
        case .poor: "GPS: poor"
        case .ok: "GPS: OK"
        case .good: "GPS: good"
        }
    }
}

private struct SignalBars: View {
    let level: Int
    let tint: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(1...3, id: \.self) { bar in
                Capsule()
                    .fill(bar <= level ? tint : Color.secondary.opacity(0.25))
                    .frame(width: 4, height: CGFloat(5 + bar * 4))
            }
        }
        .accessibilityHidden(true)
    }
}
