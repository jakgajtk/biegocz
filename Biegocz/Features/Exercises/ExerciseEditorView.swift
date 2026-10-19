import SwiftData
import SwiftUI

/// Creates a custom exercise or renames an existing custom one.
struct ExerciseEditorView: View {
    enum Mode {
        case create
        case rename(Exercise)
    }

    let mode: Mode
    var initialName = ""
    var onCreate: ((Exercise) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var muscleGroup = MuscleGroup.chest
    @State private var loggingType = LoggingType.weightReps

    private var isCreating: Bool {
        if case .create = mode { return true }
        return false
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.sentences)

                if isCreating {
                    Picker("Muscle group", selection: $muscleGroup) {
                        ForEach(MuscleGroup.allCases) { group in
                            Text(group.title).tag(group)
                        }
                    }
                    Picker("Logging type", selection: $loggingType) {
                        ForEach(LoggingType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                }
            }
            .navigationTitle(isCreating ? Text("New exercise") : Text("Rename exercise"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if case .rename(let exercise) = mode {
                    name = exercise.displayName
                } else {
                    name = initialName
                }
            }
        }
    }

    private func save() {
        switch mode {
        case .create:
            let exercise = Exercise(customName: name, muscleGroup: muscleGroup, loggingType: loggingType)
            modelContext.insert(exercise)
            onCreate?(exercise)
        case .rename(let exercise):
            exercise.customName = name
        }
        dismiss()
    }
}
