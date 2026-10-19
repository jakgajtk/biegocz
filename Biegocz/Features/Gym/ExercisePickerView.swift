import SwiftData
import SwiftUI

/// Search, recently used at the top, grouped by muscle group, "create new" inline.
struct ExercisePickerView: View {
    let onPick: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Exercise> { !$0.isArchived }) private var exercises: [Exercise]
    @State private var searchText = ""
    @State private var isCreating = false

    static let recentCount = 6

    private var matching: [Exercise] {
        exercises
            .filter { searchText.isEmpty || $0.displayName.localizedStandardContains(searchText) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// Exercises from the most recent finished workouts, most recent first.
    private var recent: [Exercise] {
        let used = exercises.compactMap { exercise in
            exercise.finishedEntries.first?.activity.map { (exercise, $0.startDate) }
        }
        return used.sorted { $0.1 > $1.1 }.prefix(Self.recentCount).map(\.0)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        isCreating = true
                    } label: {
                        Label("Create new exercise", systemImage: "plus.circle")
                            .frame(minHeight: 44)
                    }
                }

                if searchText.isEmpty, !recent.isEmpty {
                    Section("Recently used") {
                        ForEach(recent) { row(for: $0) }
                    }
                }

                let matching = matching
                ForEach(MuscleGroup.allCases) { group in
                    let items = matching.filter { $0.muscleGroup == group }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { row(for: $0) }
                        } header: {
                            Text(group.title)
                        }
                    }
                }
            }
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search exercises"))
            .overlay {
                if matching.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .sheet(isPresented: $isCreating) {
                ExerciseEditorView(mode: .create, initialName: searchText) { exercise in
                    pick(exercise)
                }
            }
        }
    }

    private func row(for exercise: Exercise) -> some View {
        Button {
            pick(exercise)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: exercise.displayName)
                    .foregroundStyle(.primary)
                Text(exercise.loggingType.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func pick(_ exercise: Exercise) {
        onPick(exercise)
        dismiss()
    }
}
