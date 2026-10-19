import Charts
import SwiftData
import SwiftUI

struct ExerciseDetailView: View {
    let exercise: Exercise

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isRenaming = false
    @State private var isConfirmingDelete = false

    private var entries: [WorkoutExercise] { exercise.finishedEntries }

    var body: some View {
        let entries = entries
        let sessions = entries.map(\.session)
        ScrollView {
            VStack(spacing: Design.spacing) {
                HStack(spacing: 8) {
                    Chip(text: Text(exercise.muscleGroup.title), systemImage: "figure.strengthtraining.traditional")
                    Chip(text: Text(exercise.loggingType.title), systemImage: "list.number")
                    if exercise.isArchived {
                        Chip(text: Text("Archived"), systemImage: "archivebox")
                    }
                    Spacer(minLength: 0)
                }
                .appearEffect()

                if exercise.isArchived {
                    Text("This exercise is archived and hidden from the picker.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if exercise.loggingType == .weightReps {
                    ProgressCards(sessions: sessions)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("History")
                            .font(.title3.weight(.bold))
                        Spacer()
                        Text("\(entries.count) sessions")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if entries.isEmpty {
                        Text("No sessions yet")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                    }
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        HistoryCard(entry: entry, loggingType: exercise.loggingType)
                            .appearEffect(delay: 0.04 * Double(min(index, 6)))
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .appBackground()
        .navigationTitle(Text(verbatim: exercise.displayName))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Actions", systemImage: "ellipsis.circle") {
                    if exercise.isCustom {
                        Button("Rename", systemImage: "pencil") {
                            isRenaming = true
                        }
                    }
                    ArchiveButton(exercise: exercise)
                    if exercise.isCustom && !exercise.hasHistory {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isRenaming) {
            ExerciseEditorView(mode: .rename(exercise))
        }
        .confirmationDialog("Delete this exercise?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                // Exercises with history are never deleted, only archived.
                guard !exercise.hasHistory else { return }
                modelContext.delete(exercise)
                dismiss()
            }
        }
    }
}

private struct Chip: View {
    let text: Text
    let systemImage: String

    var body: some View {
        Label { text } icon: { Image(systemName: systemImage) }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.cardBackground, in: .capsule)
    }
}

private struct HistoryCard: View {
    let entry: WorkoutExercise
    let loggingType: LoggingType

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: Formatters.dateTime(entry.activity?.startDate ?? .now))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(entry.sortedSets.enumerated()), id: \.element.id) { index, set in
                HStack {
                    Text(verbatim: (index + 1).formatted())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(.cardFill, in: .circle)
                        .accessibilityLabel(Text("Set \(index + 1)"))
                    Spacer()
                    Text(verbatim: SetFormatting.summary(of: set, loggingType: loggingType))
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Best set, estimated 1RM and the e1RM chart, for weight × reps exercises.
private struct ProgressCards: View {
    let sessions: [ExerciseSession]

    private struct Point: Identifiable {
        let date: Date
        let e1RM: Double
        var id: Date { date }
    }

    @State private var isChartShown = false

    var body: some View {
        let best = OneRepMax.bestSet(in: sessions.flatMap(\.doneSets))
        let points = OneRepMax.bestPerSession(sessions).map { Point(date: $0.date, e1RM: $0.e1RM) }

        if let best {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Estimated 1RM")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .textCase(.uppercase)
                        Text(verbatim: Formatters.weight(kg: best.e1RM.rounded(toPlaces: 1)))
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Best set")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .textCase(.uppercase)
                        Text(verbatim: SetFormatting.summary(of: best.set, loggingType: .weightReps))
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .monospacedDigit()
                    }
                }
                Text("Estimated with the Epley formula from sets of 1 to 12 reps.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .foregroundStyle(.white)
            .padding(20)
            .background(Design.heroGradient, in: .rect(cornerRadius: Design.cornerRadius, style: .continuous))
            .accessibilityElement(children: .combine)
            .appearEffect(delay: 0.05)
        }

        if points.count >= 2 {
            let low = points.map(\.e1RM).min() ?? 0
            VStack(alignment: .leading, spacing: 12) {
                Text("Estimated 1RM over time")
                    .font(.headline)
                Chart(points) { point in
                    AreaMark(
                        x: .value(Text("Date"), point.date, unit: .day),
                        yStart: .value(Text("Estimated 1RM"), low * 0.95),
                        yEnd: .value(Text("Estimated 1RM"), isChartShown ? point.e1RM : low * 0.95)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.02)], startPoint: .top, endPoint: .bottom)
                    )
                    LineMark(
                        x: .value(Text("Date"), point.date, unit: .day),
                        y: .value(Text("Estimated 1RM"), isChartShown ? point.e1RM : low * 0.95)
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .foregroundStyle(Color.accentColor)
                    PointMark(
                        x: .value(Text("Date"), point.date, unit: .day),
                        y: .value(Text("Estimated 1RM"), isChartShown ? point.e1RM : low * 0.95)
                    )
                    .symbolSize(point.id == points.last?.id ? 90 : 30)
                    .foregroundStyle(Color.accentColor)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel {
                    Text("kg")
                }
                .frame(height: 220)
            }
            .card()
            .appearEffect(delay: 0.1)
            .onAppear {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.85).delay(0.2)) { isChartShown = true }
            }
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
