import SwiftData
import SwiftUI

struct StartView: View {
    @Query(filter: #Predicate<Activity> { $0.isFinished }, sort: \Activity.startDate, order: .reverse)
    private var activities: [Activity]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    WeekSummaryCard(activities: activities)

                    ForEach(ActivityType.allCases) { type in
                        StartButton(title: type.title, systemImage: type.systemImage) {}
                            .disabled(true)
                    }
                    StartButton(title: "Repeat a previous workout", systemImage: "arrow.counterclockwise") {}
                        .disabled(true)
                }
                .padding()
            }
            .navigationTitle("Start")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        }
    }
}

private struct StartButton: View {
    let title: LocalizedStringResource
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .frame(width: 36)
            }
            .font(.title2.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .padding(.horizontal)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 16))
    }
}

private struct WeekSummaryCard: View {
    let activities: [Activity]

    private var thisWeek: [Activity] {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now) else { return [] }
        return activities.filter { week.contains($0.startDate) }
    }

    private var cardioMeters: Double {
        thisWeek.filter(\.type.isCardio).reduce(0) { $0 + $1.distanceMeters }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This week")
                .font(.headline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text("\(thisWeek.count) sessions")
                Spacer()
                Text(verbatim: Formatters.distance(meters: cardioMeters))
            }
            .font(.title3.weight(.semibold))
            .monospacedDigit()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    StartView()
        .modelContainer(try! PersistenceController.makeContainer(inMemory: true))
}
