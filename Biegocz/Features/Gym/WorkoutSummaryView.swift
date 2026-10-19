import SwiftUI

struct WorkoutSummaryView: View {
    let summary: WorkoutSummary
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Workout saved")
                .font(.largeTitle.weight(.bold))

            VStack(spacing: 16) {
                SummaryRow(title: "Duration", value: Formatters.duration(seconds: summary.duration))
                SummaryRow(title: "Sets", value: String(localized: "\(summary.setCount) sets"))
                SummaryRow(title: "Volume", value: Formatters.weight(kg: summary.volumeKg))
            }
            .padding()
            .background(.fill.tertiary, in: .rect(cornerRadius: 16))
            .padding(.horizontal)

            Spacer()
            Button(action: onDone) {
                Text("Done")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }
}

struct SummaryRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.title3)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WorkoutSummaryView(summary: WorkoutSummary(duration: 3_725, setCount: 18, volumeKg: 8_450), onDone: {})
}
