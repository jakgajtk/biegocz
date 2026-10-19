import SwiftUI

enum SetField: Hashable {
    case weight(UUID)
    case reps(UUID)
    case duration(UUID)
}

/// One set: big −/+ steppers with free numeric entry and a large done button.
struct SetRow: View {
    let number: Int
    @Bindable var set: ExerciseSet
    let loggingType: LoggingType
    var focusedField: FocusState<SetField?>.Binding
    let onToggleDone: () -> Void
    let onChange: () -> Void

    @AppStorage(AppSettings.weightStepKey) private var weightStep = AppSettings.defaultWeightStep

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: number.formatted())
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(set.isDone ? Color.white : Color.secondary)
                .frame(width: 26, height: 26)
                .background(set.isDone ? Color.success : Color.cardFill, in: .circle)
                .accessibilityLabel(Text("Set \(number)"))

            switch loggingType {
            case .weightReps:
                weightStepper(label: "Weight")
                repsStepper
            case .bodyweightReps:
                weightStepper(label: "Added weight")
                repsStepper
            case .duration:
                durationStepper
            }

            Spacer(minLength: 0)

            Button {
                if !set.isDone { Haptics.success() } else { Haptics.tap() }
                withAnimation(Design.bouncy) { onToggleDone() }
            } label: {
                Image(systemName: set.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(set.isDone ? Color.success : Color.secondary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: set.isDone)
                    .frame(minWidth: 48, minHeight: 48)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.isDone ? Text("Mark set as not done") : Text("Mark set as done"))
        }
        .padding(.vertical, 4)
        .listRowBackground(
            ZStack {
                Color.cardBackground
                Color.success.opacity(set.isDone ? 0.12 : 0)
            }
        )
        .animation(Design.spring, value: set.isDone)
    }

    private func weightStepper(label: LocalizedStringKey) -> some View {
        NumberStepper(
            label: label,
            unit: "kg",
            value: Binding(
                get: { set.weightKg },
                set: { set.weightKg = $0.map { max(0, $0) }; onChange() }
            ),
            format: .number.precision(.fractionLength(0...2)),
            keyboard: .decimalPad,
            width: 60,
            field: .weight(set.id),
            focusedField: focusedField,
            decrement: { set.weightKg = WeightStepper.step(set.weightKg, by: weightStep, up: false); onChange() },
            increment: { set.weightKg = WeightStepper.step(set.weightKg, by: weightStep, up: true); onChange() }
        )
    }

    private var repsStepper: some View {
        NumberStepper(
            label: "Reps",
            unit: nil,
            value: Binding(
                get: { set.reps.map(Double.init) },
                set: { set.reps = $0.map { max(0, Int($0.rounded())) }; onChange() }
            ),
            format: .number.precision(.fractionLength(0)),
            keyboard: .numberPad,
            width: 38,
            field: .reps(set.id),
            focusedField: focusedField,
            decrement: { set.reps = max(0, (set.reps ?? 0) - 1); onChange() },
            increment: { set.reps = (set.reps ?? 0) + 1; onChange() }
        )
    }

    private var durationStepper: some View {
        NumberStepper(
            label: "Seconds",
            unit: "s",
            value: Binding(
                get: { set.durationSeconds },
                set: { set.durationSeconds = $0.map { max(0, $0.rounded()) }; onChange() }
            ),
            format: .number.precision(.fractionLength(0)),
            keyboard: .numberPad,
            width: 56,
            field: .duration(set.id),
            focusedField: focusedField,
            decrement: { set.durationSeconds = max(0, (set.durationSeconds ?? 0) - 15); onChange() },
            increment: { set.durationSeconds = (set.durationSeconds ?? 0) + 15; onChange() }
        )
    }
}

private struct NumberStepper: View {
    let label: LocalizedStringKey
    let unit: LocalizedStringKey?
    @Binding var value: Double?
    let format: FloatingPointFormatStyle<Double>
    let keyboard: UIKeyboardType
    let width: CGFloat
    let field: SetField
    var focusedField: FocusState<SetField?>.Binding
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            stepButton("minus", action: decrement)
                .accessibilityLabel(Text("Decrease"))
            VStack(spacing: -2) {
                TextField(label, value: $value, format: format, prompt: Text(verbatim: "0"))
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.center)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .focused(focusedField, equals: field)
                    .frame(width: width)
                if let unit {
                    Text(unit)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            stepButton("plus", action: increment)
                .accessibilityLabel(Text("Increase"))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(label))
    }

    private func stepButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.bold))
                .foregroundStyle(.tint)
                .frame(width: 34, height: 44)
                .background(.cardFill, in: .rect(cornerRadius: 12, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.pressable)
    }
}
