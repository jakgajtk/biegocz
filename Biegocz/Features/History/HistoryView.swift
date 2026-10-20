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

    /// Newest month first, activities newest first within each.
    private var months: [(month: Date, activities: [Activity])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { activity in
            calendar.dateInterval(of: .month, for: activity.startDate)?.start ?? activity.startDate
        }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !filtered.isEmpty {
                    Section {
                        HistoryOverview(activities: filtered, filter: filter)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                ForEach(months, id: \.month) { month in
                    Section {
                        ForEach(month.activities) { activity in
                            NavigationLink(value: activity) {
                                ActivityRow(activity: activity)
                            }
                            .cardRow()
                        }
                    } header: {
                        MonthHeader(month: month.month, activities: month.activities)
                    }
                }
            }
            .appListStyle()
            .animation(Design.spring, value: filter)
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
                .onChange(of: filter) { Haptics.selection() }
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView {
                        Label("No activities yet", systemImage: filter?.systemImage ?? "sparkles")
                            .symbolEffect(.bounce, value: filter)
                    } description: {
                        Text("Finished workouts, runs and rides show up here.")
                    }
                }
            }
        }
    }
}

/// "October 2026" with the month's distance and active time on the right.
private struct MonthHeader: View {
    let month: Date
    let activities: [Activity]

    var body: some View {
        let distance = activities.reduce(0) { $0 + $1.distanceMeters }
        let time = activities.reduce(0) { $0 + $1.summary.activeSeconds }
        HStack {
            Text(verbatim: month.formatted(.dateTime.month(.wide).year().locale(Formatters.appLocale)))
            Spacer()
            Group {
                if distance > 0 {
                    Text(verbatim: "\(Formatters.distance(meters: distance, fractionDigits: 1)) · \(Formatters.totalTime(seconds: time))")
                } else {
                    Text(verbatim: Formatters.totalTime(seconds: time))
                }
            }
            .monospacedDigit()
            .textCase(nil)
        }
    }
}

private struct ActivityRow: View {
    let activity: Activity

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(systemImage: activity.type.systemImage, tint: activity.type.tint, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(activity.type.title)
                    .font(.headline)
                Text(verbatim: Formatters.dayAndTime(activity.startDate))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Group {
                    if activity.type.isCardio {
                        Text(verbatim: Formatters.distance(meters: activity.distanceMeters))
                    } else {
                        Text("\(activity.completedSetCount) sets")
                    }
                }
                .font(.system(.headline, design: .rounded, weight: .bold))
                Text(verbatim: Formatters.duration(seconds: activity.type.isCardio ? activity.movingSeconds : activity.elapsedSeconds))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HistoryView()
        .modelContainer(try! PersistenceController.makeContainer(inMemory: true))
}
