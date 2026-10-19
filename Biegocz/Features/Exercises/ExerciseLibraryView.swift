import SwiftData
import SwiftUI

struct ExerciseLibraryView: View {
    @Query private var exercises: [Exercise]
    @State private var searchText = ""
    @State private var showArchived = false
    @State private var isCreating = false

    private var visible: [Exercise] {
        exercises
            .filter { showArchived || !$0.isArchived }
            .filter { searchText.isEmpty || $0.displayName.localizedStandardContains(searchText) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                let visible = visible
                ForEach(MuscleGroup.allCases) { group in
                    let items = visible.filter { $0.muscleGroup == group }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { exercise in
                                NavigationLink(value: exercise) {
                                    ExerciseRow(exercise: exercise)
                                }
                                .swipeActions {
                                    ArchiveButton(exercise: exercise)
                                }
                            }
                        } header: {
                            Text(group.title)
                        }
                    }
                }
            }
            .navigationTitle("Exercises")
            .navigationDestination(for: Exercise.self) { exercise in
                ExerciseDetailView(exercise: exercise)
            }
            .searchable(text: $searchText, prompt: Text("Search exercises"))
            .overlay {
                if visible.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New exercise", systemImage: "plus") {
                        isCreating = true
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu("Options", systemImage: "line.3.horizontal.decrease.circle") {
                        Toggle("Show archived", isOn: $showArchived)
                    }
                }
            }
            .sheet(isPresented: $isCreating) {
                ExerciseEditorView(mode: .create)
            }
        }
    }
}

private struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: exercise.displayName)
                .foregroundStyle(exercise.isArchived ? .secondary : .primary)
            HStack(spacing: 6) {
                Text(exercise.loggingType.title)
                if exercise.isArchived {
                    Text("Archived")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct ArchiveButton: View {
    let exercise: Exercise

    var body: some View {
        if exercise.isArchived {
            Button("Unarchive", systemImage: "tray.and.arrow.up") {
                exercise.isArchived = false
            }
            .tint(.blue)
        } else {
            Button("Archive", systemImage: "archivebox") {
                exercise.isArchived = true
            }
            .tint(.orange)
        }
    }
}

#Preview {
    let container = try! PersistenceController.makeContainer(inMemory: true)
    try! ExerciseSeeder.seedIfNeeded(in: container.mainContext)
    return ExerciseLibraryView()
        .modelContainer(container)
}
