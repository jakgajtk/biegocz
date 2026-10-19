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
        List {
            Section {
                LabeledContent {
                    Text(exercise.muscleGroup.title)
                } label: {
                    Text("Muscle group")
                }
                LabeledContent {
                    Text(exercise.loggingType.title)
                } label: {
                    Text("Logging type")
                }
                if exercise.isArchived {
                    Text("This exercise is archived and hidden from the picker.")
                        .foregroundStyle(.secondary)
                }
            }

            if exercise.loggingType == .weightReps {
                ProgressSections(sessions: sessions)
            }

            Section("History") {
                if entries.isEmpty {
                    Text("No sessions yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: Formatters.dateTime(entry.activity?.startDate ?? .now))
                            .font(.headline)
                        ForEach(Array(entry.sortedSets.enumerated()), id: \.element.id) { index, set in
                            HStack {
                                Text("Set \(index + 1)")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(verbatim: SetFormatting.summary(of: set, loggingType: exercise.loggingType))
                                    .monospacedDigit()
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(Text(verbatim: exercise.displayName))
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

/// Best set, estimated 1RM and the e1RM chart, for weight × reps exercises.
private struct ProgressSections: View {
    let sessions: [ExerciseSession]

    private struct Point: Identifiable {
        let date: Date
        let e1RM: Double
        var id: Date { date }
    }

    var body: some View {
        let best = OneRepMax.bestSet(in: sessions.flatMap(\.doneSets))
        let points = OneRepMax.bestPerSession(sessions).map { Point(date: $0.date, e1RM: $0.e1RM) }

        if let best {
            Section {
                LabeledContent {
                    Text(verbatim: SetFormatting.summary(of: best.set, loggingType: .weightReps))
                        .monospacedDigit()
                } label: {
                    Text("Best set")
                }
                LabeledContent {
                    Text(verbatim: Formatters.weight(kg: best.e1RM.rounded(toPlaces: 1)))
                        .monospacedDigit()
                } label: {
                    Text("Estimated 1RM")
                }
            } footer: {
                Text("Estimated with the Epley formula from sets of 1 to 12 reps.")
            }
        }

        if points.count >= 2 {
            Section("Estimated 1RM over time") {
                Chart(points) { point in
                    LineMark(
                        x: .value(Text("Date"), point.date, unit: .day),
                        y: .value(Text("Estimated 1RM"), point.e1RM)
                    )
                    .interpolationMethod(.monotone)
                    PointMark(
                        x: .value(Text("Date"), point.date, unit: .day),
                        y: .value(Text("Estimated 1RM"), point.e1RM)
                    )
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel {
                    Text("kg")
                }
                .frame(height: 220)
                .padding(.vertical, 8)
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
