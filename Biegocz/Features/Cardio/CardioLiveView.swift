import SwiftUI

struct CardioLiveView: View {
    let model: CardioSessionModel
    let onDiscard: () -> Void
    @State private var isConfirmingDiscard = false

    private var engine: CardioEngine { model.engine }
    private var isRunning: Bool { engine.state == .running }
    private var tint: Color { model.type.tint }

    var body: some View {
        VStack(spacing: 0) {
            RouteMap(segments: engine.segments, current: model.lastFix, followsCurrent: true, tint: tint, planned: model.plannedRoute)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    // Soft fade from the map into the panel.
                    LinearGradient(colors: [.clear, .appBackground], startPoint: .top, endPoint: .bottom)
                        .frame(height: 40)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .top) {
                    if !isRunning {
                        StatusBanner(state: engine.state)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

            VStack(spacing: 14) {
                VStack(spacing: 0) {
                    Text("Time")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    // Moving time, so the clock stops while paused, like a stopwatch.
                    Text(verbatim: Formatters.duration(seconds: engine.movingTime(at: model.now)))
                        .font(.system(size: 68, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)

                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        MetricTile(title: "Distance", value: Formatters.distance(meters: engine.distance), emphasized: true, tint: tint)
                        if model.type == .run {
                            MetricTile(title: "Pace", value: paceText(engine.currentSpeed(at: model.now)))
                        } else {
                            MetricTile(title: "Speed", value: speedText(engine.currentSpeed(at: model.now)))
                        }
                    }
                    GridRow {
                        MetricTile(title: "Elapsed time", value: Formatters.duration(seconds: engine.elapsedTime(at: model.now)))
                        if model.type == .run {
                            MetricTile(title: "Avg pace", value: paceText(engine.averageSpeed(at: model.now)))
                        } else {
                            MetricTile(title: "Avg speed", value: speedText(engine.averageSpeed(at: model.now)))
                        }
                    }
                }
                .opacity(isRunning ? 1 : 0.55)

                controls
            }
            .padding()
            .background(Color.appBackground)
        }
        .animation(Design.spring, value: engine.state)
        .animation(Design.spring, value: model.now)
        .confirmationDialog(
            "Discard this activity?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                model.discard()
                onDiscard()
            }
        } message: {
            Text("The route and all stats will be deleted.")
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.firm()
                if engine.state == .paused {
                    model.resume()
                } else {
                    model.pause()
                }
            } label: {
                Label {
                    Text(engine.state == .paused ? "Resume" : "Pause")
                } icon: {
                    Image(systemName: engine.state == .paused ? "play.fill" : "pause.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .buttonStyle(.prominent(engine.state == .paused ? .success : .warning, height: 72))

            HoldToConfirmButton(title: "Finish", caption: "Hold", systemImage: "stop.fill") {
                model.finish()
            }
        }
        if engine.state == .paused {
            Button("Discard", role: .destructive) {
                isConfirmingDiscard = true
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
            .transition(.opacity)
        }
    }

    private func paceText(_ speed: Double?) -> String {
        let pace = Formatters.pace(secondsPerKilometer: Pace.secondsPerKilometer(metersPerSecond: speed))
        return String(localized: "\(pace) /km")
    }

    private func speedText(_ speed: Double?) -> String {
        guard let speed else { return "--" }
        return Formatters.speed(metersPerSecond: speed)
    }
}

private struct MetricTile: View {
    let title: LocalizedStringKey
    let value: String
    var emphasized = false
    var tint: Color = .accentColor

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(emphasized ? tint : .secondary)
                .textCase(.uppercase)
            Text(verbatim: value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.cardBackground, in: .rect(cornerRadius: Design.smallCornerRadius + 4, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct StatusBanner: View {
    let state: CardioEngine.State

    var body: some View {
        Label {
            Text(state == .autoPaused ? "Auto-paused" : "Paused")
        } icon: {
            Image(systemName: "pause.circle.fill")
                .symbolEffect(.pulse, options: .repeating)
        }
        .font(.headline)
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.warning.gradient, in: .capsule)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

/// Runs `action` only after being held for a moment, so it can't be
/// triggered by accident. VoiceOver users activate it directly.
struct HoldToConfirmButton: View {
    let title: LocalizedStringKey
    let caption: LocalizedStringKey
    let systemImage: String
    var duration: TimeInterval = 1.2
    let action: () -> Void

    @State private var progress: CGFloat = 0
    @State private var isPressing = false

    var body: some View {
        VStack(spacing: 0) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.bold))
            Text(caption)
                .font(.caption.weight(.semibold))
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.danger.opacity(0.55))
                    Rectangle().fill(Color.danger)
                        .frame(width: geometry.size.width * progress)
                }
            }
        }
        .clipShape(.capsule)
        .contentShape(.capsule)
        .scaleEffect(isPressing ? 0.96 : 1)
        .animation(Design.spring, value: isPressing)
        .onLongPressGesture(minimumDuration: duration) {
            progress = 0
            Haptics.success()
            action()
        } onPressingChanged: { pressing in
            isPressing = pressing
            if pressing { Haptics.tap() }
            withAnimation(pressing ? .linear(duration: duration) : .easeOut(duration: 0.2)) {
                progress = pressing ? 1 : 0
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}
