import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(filter: #Predicate<Activity> { $0.isFinished }, sort: \Activity.startDate, order: .reverse)
    private var activities: [Activity]
    @State private var filter: ActivityType?

    private var filtered: [Activity] {
        guard let filter else { return activities }
        return activities.filter { $0.type == filter }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { activity in
                NavigationLink(value: activity) {
                    ActivityRow(activity: activity)
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: Activity.self) { activity in
                ActivityDetailView(activity: activity)
            }
            .safeAreaInset(edge: .top) {
                Picker("Activity type", selection: $filter) {
                    Text("All").tag(ActivityType?.none)
                    ForEach(ActivityType.allCases) { type in
                        Text(type.title).tag(ActivityType?.some(type))
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        "No activities yet",
                        systemImage: "clock",
                        description: Text("Finished workouts, runs and rides show up here.")
                    )
                }
            }
        }
    }
}

private struct ActivityRow: View {
    let activity: Activity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.type.systemImage)
                .font(.title2)
                .frame(width: 36)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.type.title)
                    .font(.headline)
                Text(verbatim: Formatters.dateTime(activity.startDate))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Group {
                if activity.type.isCardio {
                    Text(verbatim: Formatters.distance(meters: activity.distanceMeters))
                } else {
                    Text("\(activity.completedSetCount) sets")
                }
            }
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
        }
    }
}

#Preview {
    HistoryView()
        .modelContainer(try! PersistenceController.makeContainer(inMemory: true))
}
