import SwiftUI

struct CardioLiveView: View {
    let model: CardioSessionModel
    let onDiscard: () -> Void
    @State private var isConfirmingDiscard = false

    private var engine: CardioEngine { model.engine }

    var body: some View {
        VStack(spacing: 0) {
            RouteMap(segments: engine.segments, current: model.lastFix, followsCurrent: true)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .top) {
                    if engine.state != .running {
                        StatusBanner(state: engine.state)
                            .padding(.top, 8)
                    }
                }

            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    Text("Time")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(verbatim: Formatters.duration(seconds: engine.elapsedTime(at: model.now)))
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)

                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        MetricTile(title: "Distance", value: Formatters.distance(meters: engine.distance))
                        if model.type == .run {
                            MetricTile(title: "Pace", value: paceText(engine.currentSpeed(at: model.now)))
                        } else {
                            MetricTile(title: "Speed", value: speedText(engine.currentSpeed(at: model.now)))
                        }
                    }
                    GridRow {
                        MetricTile(title: "Moving time", value: Formatters.duration(seconds: engine.movingTime(at: model.now)))
                        if model.type == .run {
                            MetricTile(title: "Avg pace", value: paceText(engine.averageSpeed(at: model.now)))
                        } else {
                            MetricTile(title: "Avg speed", value: speedText(engine.averageSpeed(at: model.now)))
                        }
                    }
                }

                controls
            }
            .padding()
            .background(.background)
        }
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
            if engine.state == .paused {
                Button {
                    model.resume()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .font(.title2.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 72)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            } else {
                Button {
                    model.pause()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .font(.title2.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 72)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

            HoldToConfirmButton(title: "Finish", caption: "Hold", systemImage: "stop.fill") {
                model.finish()
            }
        }
        if engine.state == .paused {
            Button("Discard", role: .destructive) {
                isConfirmingDiscard = true
            }
            .frame(minHeight: 44)
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

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.fill.tertiary, in: .rect(cornerRadius: 14))
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
        }
        .font(.headline)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: .capsule)
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

    var body: some View {
        VStack(spacing: 0) {
            Label(title, systemImage: systemImage)
                .font(.title2.weight(.bold))
            Text(caption)
                .font(.caption.weight(.semibold))
                .opacity(0.85)
        }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.red.opacity(0.55))
                        Rectangle().fill(Color.red)
                            .frame(width: geometry.size.width * progress)
                    }
                }
            }
            .clipShape(.capsule)
            .contentShape(.capsule)
            .onLongPressGesture(minimumDuration: duration) {
                progress = 0
                action()
            } onPressingChanged: { pressing in
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
