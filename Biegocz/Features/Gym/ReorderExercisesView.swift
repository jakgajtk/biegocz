import SwiftUI

struct ReorderExercisesView: View {
    let model: GymSessionModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.entries) { entry in
                    Text(verbatim: entry.exercise?.displayName ?? "")
                        .font(.body.weight(.medium))
                        .frame(minHeight: 44, alignment: .leading)
                        .cardRow()
                }
                .onMove { source, destination in
                    model.moveExercises(from: source, to: destination)
                }
                .onDelete { offsets in
                    let entries = model.entries
                    for index in offsets {
                        model.removeExercise(entries[index])
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .appListStyle()
            .navigationTitle("Reorder exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
