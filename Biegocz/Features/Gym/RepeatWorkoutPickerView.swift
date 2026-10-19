import SwiftData
import SwiftUI

/// Lists past gym workouts to repeat.
struct RepeatWorkoutPickerView: View {
    let onPick: (Activity) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(
        filter: #Predicate<Activity> { $0.isFinished && $0.typeRaw == "gym" },
        sort: \Activity.startDate,
        order: .reverse
    )
    private var workouts: [Activity]

    var body: some View {
        NavigationStack {
            List(workouts) { workout in
                Button {
                    onPick(workout)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: Formatters.dateTime(workout.startDate))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(verbatim: workout.sortedExercises.compactMap { $0.exercise?.displayName }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
                }
            }
            .navigationTitle("Repeat a workout")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "No gym workouts yet",
                        systemImage: "dumbbell",
                        description: Text("Finished gym workouts can be repeated from here.")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
    }
}
