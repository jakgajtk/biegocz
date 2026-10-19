import SwiftUI

struct WorkoutSummaryView: View {
    let summary: WorkoutSummary
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0
    @State private var celebrate = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                if !reduceMotion {
                    ForEach(0..<3) { ring in
                        Circle()
                            .stroke(Color.success.opacity(0.35), lineWidth: 2)
                            .scaleEffect(celebrate ? 1.8 + Double(ring) * 0.35 : 0.6)
                            .opacity(celebrate ? 0 : 0.8)
                            .animation(.easeOut(duration: 1.1).delay(Double(ring) * 0.12), value: celebrate)
                    }
                }
                Circle()
                    .fill(Color.success.opacity(0.14))
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(Color.success)
                    .symbolEffect(.bounce, value: celebrate)
            }
            .frame(width: 120, height: 120)
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Workout saved")
                    .font(.largeTitle.weight(.bold))
                Text("Great work. See you next time!")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .appearEffect(delay: 0.15)

            HStack(spacing: 12) {
                SummaryTile(title: "Duration", systemImage: "clock.fill", tint: .accentColor) {
                    CountingText(value: summary.duration * progress) { Formatters.duration(seconds: $0) }
                }
                .appearEffect(delay: 0.25)
                SummaryTile(title: "Sets", systemImage: "checkmark.circle.fill", tint: .success) {
                    CountingText(value: Double(summary.setCount) * progress) { Int($0.rounded()).formatted() }
                }
                .appearEffect(delay: 0.32)
                SummaryTile(title: "Volume", systemImage: "scalemass.fill", tint: .gymTint) {
                    CountingText(value: summary.volumeKg * progress) { Formatters.weight(kg: $0.rounded()) }
                }
                .appearEffect(delay: 0.39)
            }
            .padding(.horizontal)

            Spacer()

            Button("Done", action: onDone)
                .buttonStyle(.prominent())
                .padding(.horizontal)
                .padding(.bottom)
                .appearEffect(delay: 0.5)
        }
        .appBackground()
        .onAppear {
            Haptics.success()
            celebrate = true
            if reduceMotion {
                progress = 1
            } else {
                withAnimation(.easeOut(duration: 1.2).delay(0.3)) { progress = 1 }
            }
        }
    }
}

private struct SummaryTile<Value: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color
    @ViewBuilder let value: () -> Value

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            value()
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

/// Text for a number that counts up smoothly when its value is animated.
struct CountingText: View, Animatable {
    var value: Double
    let format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(verbatim: format(value))
    }
}

#Preview {
    WorkoutSummaryView(summary: WorkoutSummary(duration: 3_725, setCount: 18, volumeKg: 8_450), onDone: {})
}
