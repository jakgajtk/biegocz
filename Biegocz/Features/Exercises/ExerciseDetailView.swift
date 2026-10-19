import SwiftData
import SwiftUI

struct ExerciseDetailView: View {
    let exercise: Exercise

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isRenaming = false
    @State private var isConfirmingDelete = false

    var body: some View {
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

            Section("History") {
                if exercise.hasHistory {
                    Text("\(exercise.workoutEntries.count) sessions")
                } else {
                    Text("No sessions yet")
                        .foregroundStyle(.secondary)
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
