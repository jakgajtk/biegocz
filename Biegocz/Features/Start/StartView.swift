import SwiftData
import SwiftUI

struct StartView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionCoordinator.self) private var coordinator
    @Query(filter: #Predicate<Activity> { $0.isFinished }, sort: \Activity.startDate, order: .reverse)
    private var activities: [Activity]
    @State private var isPickingWorkoutToRepeat = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.spacing) {
                    GreetingHeader()
                        .appearEffect()

                    WeekCard(activities: activities)
                        .appearEffect(delay: 0.05)

                    ActivityTile(type: .gym, last: lastDate(of: .gym), wide: true) {
                        Haptics.tap()
                        coordinator.startGym(in: modelContext)
                    }
                    .appearEffect(delay: 0.1)

                    HStack(spacing: Design.spacing) {
                        ActivityTile(type: .run, last: lastDate(of: .run)) {
                            Haptics.tap()
                            coordinator.prepareCardio(.run)
                        }
                        ActivityTile(type: .ride, last: lastDate(of: .ride)) {
                            Haptics.tap()
                            coordinator.prepareCardio(.ride)
                        }
                    }
                    .appearEffect(delay: 0.15)

                    Button {
                        Haptics.tap()
                        isPickingWorkoutToRepeat = true
                    } label: {
                        HStack(spacing: 14) {
                            IconBadge(systemImage: "arrow.counterclockwise", tint: .accentColor, size: 40)
                            Text("Repeat a previous workout")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .card(padding: 14)
                    }
                    .buttonStyle(.pressable)
                    .appearEffect(delay: 0.2)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .appBackground()
            .sheet(isPresented: $isPickingWorkoutToRepeat) {
                RepeatWorkoutPickerView { workout in
                    coordinator.repeatGym(workout, in: modelContext)
                }
            }
        }
    }

    private func lastDate(of type: ActivityType) -> Date? {
        activities.first { $0.type == type }?.startDate
    }
}

private struct GreetingHeader: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(greeting(at: context.date))
                    .font(.largeTitle.weight(.bold))
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }

    private func greeting(at date: Date) -> LocalizedStringKey {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
}

/// Navy hero card: sessions and distance this week, plus a day-by-day strip.
private struct WeekCard: View {
    let activities: [Activity]

    private var week: DateInterval? {
        Calendar.current.dateInterval(of: .weekOfYear, for: .now)
    }

    private var thisWeek: [Activity] {
        guard let week else { return [] }
        return activities.filter { week.contains($0.startDate) }
    }

    private var cardioMeters: Double {
        thisWeek.filter(\.type.isCardio).reduce(0) { $0 + $1.distanceMeters }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("This week")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .textCase(.uppercase)

            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Sessions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .textCase(.uppercase)
                    Text(verbatim: thisWeek.count.formatted())
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(value: Double(thisWeek.count)))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Distance")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .textCase(.uppercase)
                    Text(verbatim: Formatters.distance(meters: cardioMeters))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(value: cardioMeters))
                }
            }
            .monospacedDigit()

            if let week {
                DayStrip(week: week, activities: thisWeek)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(Design.heroGradient, in: .rect(cornerRadius: Design.cornerRadius, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "figure.run")
                .font(.system(size: 120, weight: .black))
                .foregroundStyle(.white.opacity(0.05))
                .offset(x: 10, y: -10)
                .accessibilityHidden(true)
        }
        .clipShape(.rect(cornerRadius: Design.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Seven days with a dot per activity type done that day; today is ringed.
private struct DayStrip: View {
    let week: DateInterval
    let activities: [Activity]

    private var days: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: week.start) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let types = Set(activities.filter { Calendar.current.isDate($0.startDate, inSameDayAs: day) }.map(\.type))
                let isToday = Calendar.current.isDateInToday(day)
                VStack(spacing: 6) {
                    Text(verbatim: day.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(isToday ? 1 : 0.6))
                    ZStack {
                        Circle()
                            .fill(.white.opacity(types.isEmpty ? 0.08 : 0.18))
                        Circle()
                            .strokeBorder(.white.opacity(isToday ? 0.9 : 0), lineWidth: 2)
                        HStack(spacing: 2) {
                            ForEach(ActivityType.allCases.filter(types.contains)) { type in
                                Circle()
                                    .fill(type.tint)
                                    .frame(width: 7, height: 7)
                            }
                        }
                    }
                    .frame(width: 34, height: 34)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A big tappable tile for starting an activity.
private struct ActivityTile: View {
    let type: ActivityType
    let last: Date?
    var wide = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if wide {
                    HStack(spacing: 14) {
                        IconBadge(systemImage: type.systemImage, tint: type.tint, size: 56)
                        titles
                        Spacer(minLength: 0)
                        playBadge
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            IconBadge(systemImage: type.systemImage, tint: type.tint, size: 52)
                            Spacer()
                            playBadge
                        }
                        titles
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .buttonStyle(.pressable)
        .accessibilityHint(Text(verbatim: lastText))
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(type.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
            Text(verbatim: lastText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var playBadge: some View {
        Image(systemName: "play.fill")
            .font(.footnote.weight(.bold))
            .foregroundStyle(type.tint)
            .frame(width: 32, height: 32)
            .background(type.tint.opacity(0.14), in: .circle)
    }

    private var lastText: String {
        guard let last else { return String(localized: "Not yet") }
        let relative = last.formatted(.relative(presentation: .named, unitsStyle: .wide))
        return String(localized: "Last: \(relative)")
    }
}

#Preview {
    StartView()
        .modelContainer(try! PersistenceController.makeContainer(inMemory: true))
        .environment(SessionCoordinator(
            restNotifier: NoOpRestNotifier(), location: GPXReplayLocationProvider(), health: NoOpHealthStore()
        ))
}
