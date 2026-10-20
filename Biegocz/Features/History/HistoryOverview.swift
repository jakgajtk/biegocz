import Charts
import SwiftUI

/// Top of History: totals for this week, month or year with a chart of the
/// previous ones, the weekly streak and personal bests. Follows the type filter.
struct HistoryOverview: View {
    let activities: [Activity]
    let filter: ActivityType?

    @AppStorage("history.period") private var period = StatsPeriod.month
    /// A period picked by dragging over the chart; `nil` shows the current one.
    @State private var selectedDate: Date?

    private var summaries: [ActivitySummary] { activities.map(\.summary) }

    var body: some View {
        let summaries = summaries
        let buckets = HistoryStats.buckets(summaries, period: period, count: period.chartCount, now: .now)
        let shownIndex = selectedIndex(in: buckets) ?? buckets.count - 1
        VStack(alignment: .leading, spacing: Design.spacing) {
            if buckets.indices.contains(shownIndex) {
                let isCurrent = shownIndex == buckets.count - 1
                // The current period is compared with the same stretch of the last one.
                let previous = isCurrent
                    ? HistoryStats.previousToDate(summaries, period: period, now: .now)
                    : (shownIndex > 0 ? buckets[shownIndex - 1] : nil)
                hero(buckets: buckets, shownIndex: shownIndex, previous: previous, streak: HistoryStats.weekStreak(summaries, now: .now))
            }
            RecordsStrip(records: HistoryStats.records(summaries), activities: activities)
        }
        .sensoryFeedback(.selection, trigger: shownIndex)
        .animation(Design.spring, value: period)
        .animation(Design.spring, value: filter)
    }

    private func selectedIndex(in buckets: [PeriodTotals]) -> Int? {
        guard let selectedDate else { return nil }
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: period.component, for: selectedDate)?.start
        return buckets.firstIndex { $0.start == start }
    }

    // MARK: Hero

    private func hero(buckets: [PeriodTotals], shownIndex: Int, previous: PeriodTotals?, streak: Int) -> some View {
        let shown = buckets[shownIndex]
        let isCurrent = shownIndex == buckets.count - 1
        let metric = Metric(filter: filter)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                periodMenu(isCurrent: isCurrent, shown: shown)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: metric.formatted(metric.value(of: shown)))
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: metric.value(of: shown)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let previous, let change = HistoryStats.change(from: metric.value(of: previous), to: metric.value(of: shown)) {
                    ChangeChip(change: change, label: isCurrent ? period.toDateComparisonTitle : period.comparisonTitle)
                        .transition(.opacity)
                }
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 24) {
                ForEach(metric.secondary, id: \.self) { secondary in
                    StatView(title: secondary.title, value: secondary.formatted(secondary.value(of: shown)), valueFont: .system(.title3, design: .rounded, weight: .bold))
                }
                if streak > 1 {
                    // Weeks in a row with at least one activity.
                    StatView(title: "Streak", value: String(localized: "\(streak) weeks"), valueFont: .system(.title3, design: .rounded, weight: .bold))
                }
            }
            .foregroundStyle(.white)

            OverviewChart(buckets: buckets, period: period, metric: metric, filter: filter, shownIndex: shownIndex, selectedDate: $selectedDate)
                .frame(height: 120)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .padding(20)
        .background(Design.heroGradient, in: .rect(cornerRadius: Design.cornerRadius, style: .continuous))
        .animation(Design.spring, value: shownIndex)
    }

    private func periodMenu(isCurrent: Bool, shown: PeriodTotals) -> some View {
        Menu {
            Picker("Period", selection: $period) {
                ForEach(StatsPeriod.allCases) { option in
                    Text(option.currentTitle).tag(option)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Group {
                    if isCurrent {
                        Text(period.currentTitle)
                    } else {
                        Text(verbatim: period.title(for: shown.start))
                    }
                }
                .contentTransition(.opacity)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(.white.opacity(0.8))
        }
        .onChange(of: period) {
            selectedDate = nil
            Haptics.selection()
        }
    }
}

// MARK: - Metric

/// What the overview leads with, depending on the filter: distance for runs
/// and rides, sessions for the gym, active time for everything.
private enum Metric: Hashable {
    case distance, time, count, volume

    init(filter: ActivityType?) {
        switch filter {
        case .run, .ride: self = .distance
        case .gym: self = .count
        case nil: self = .time
        }
    }

    var secondary: [Metric] {
        switch self {
        case .distance: [.time, .count]
        case .count: [.time, .volume]
        case .time, .volume: [.count, .distance]
        }
    }

    func value(of totals: PeriodTotals) -> Double {
        switch self {
        case .distance: totals.distance
        case .time: totals.activeSeconds
        case .count: Double(totals.count)
        case .volume: totals.volumeKg
        }
    }

    /// Value for the chart, in friendlier units: km, hours, sessions, tonnes.
    func chartValue(_ value: Double) -> Double {
        switch self {
        case .distance: value / 1000
        case .time: value / 3600
        case .count: value
        case .volume: value / 1000
        }
    }

    func formatted(_ value: Double) -> String {
        switch self {
        case .distance: Formatters.distance(meters: value, fractionDigits: 1)
        case .time: Formatters.totalTime(seconds: value)
        case .count: Int(value).formatted()
        case .volume: Formatters.weight(kg: value.rounded())
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .distance: "Distance"
        case .time: "Time"
        case .count: "Sessions"
        case .volume: "Volume"
        }
    }
}

private struct ChangeChip: View {
    let change: Double
    let label: LocalizedStringKey

    var body: some View {
        HStack(spacing: 6) {
            Label {
                Text(verbatim: Formatters.change(change))
            } icon: {
                Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(change >= 0 ? Color.success : .white.opacity(0.75))
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Chart

private struct OverviewChart: View {
    let buckets: [PeriodTotals]
    let period: StatsPeriod
    let metric: Metric
    let filter: ActivityType?
    let shownIndex: Int
    @Binding var selectedDate: Date?

    var body: some View {
        Chart {
            ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                let highlighted = index == shownIndex
                if filter == nil {
                    // Everything: time stacked by activity type.
                    ForEach(ActivityType.allCases) { type in
                        BarMark(
                            x: .value("Period", bucket.start, unit: period.component),
                            y: .value("Value", metric.chartValue(bucket.activeSecondsByType[type] ?? 0))
                        )
                        .foregroundStyle(type.tint.opacity(highlighted ? 1 : 0.5))
                        .cornerRadius(3)
                    }
                } else {
                    BarMark(
                        x: .value("Period", bucket.start, unit: period.component),
                        y: .value("Value", metric.chartValue(metric.value(of: bucket)))
                    )
                    .foregroundStyle(.white.opacity(highlighted ? 1 : 0.35))
                    .cornerRadius(3)
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.15))
                AxisValueLabel().foregroundStyle(.white.opacity(0.6))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: period.component, count: period.axisStride)) { value in
                AxisValueLabel(format: period.axisFormat, centered: true)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Records

private struct RecordsStrip: View {
    let records: [PersonalRecord]
    let activities: [Activity]

    var body: some View {
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Personal bests")
                    .font(.title3.weight(.bold))
                    .padding(.horizontal, 4)
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(records) { record in
                            if let activity = activities.first(where: { $0.id == record.activityID }) {
                                NavigationLink(value: activity) {
                                    RecordTile(record: record)
                                }
                                .buttonStyle(.pressable)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }
    }
}

private struct RecordTile: View {
    let record: PersonalRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IconBadge(systemImage: record.kind.systemImage, tint: record.kind.tint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.kind.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .lineLimit(2, reservesSpace: true)
                Text(verbatim: record.kind.formatted(record.value))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(verbatim: record.date.formatted(.dateTime.day().month(.abbreviated).year().locale(Formatters.appLocale)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 160, alignment: .leading)
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

private extension PersonalRecord.Kind {
    var title: LocalizedStringKey {
        switch self {
        case .longestRun: "Longest run"
        case .fastestRun: "Fastest run (5 km+)"
        case .longestRide: "Longest ride"
        case .fastestRide: "Fastest ride (10 km+)"
        case .biggestClimb: "Biggest climb"
        case .biggestGymVolume: "Biggest workout"
        }
    }

    var systemImage: String {
        switch self {
        case .longestRun, .fastestRun: ActivityType.run.systemImage
        case .longestRide, .fastestRide: ActivityType.ride.systemImage
        case .biggestClimb: "mountain.2.fill"
        case .biggestGymVolume: ActivityType.gym.systemImage
        }
    }

    var tint: Color {
        switch self {
        case .longestRun, .fastestRun: ActivityType.run.tint
        case .longestRide, .fastestRide: ActivityType.ride.tint
        case .biggestClimb: .warning
        case .biggestGymVolume: ActivityType.gym.tint
        }
    }

    func formatted(_ value: Double) -> String {
        switch self {
        case .longestRun, .longestRide: Formatters.distance(meters: value)
        case .fastestRun: String(localized: "\(Formatters.pace(secondsPerKilometer: value)) /km")
        case .fastestRide: Formatters.speed(metersPerSecond: value)
        case .biggestClimb: Formatters.elevation(meters: value)
        case .biggestGymVolume: Formatters.weight(kg: value.rounded())
        }
    }
}

// MARK: - Period texts

private extension StatsPeriod {
    var currentTitle: LocalizedStringKey {
        switch self {
        case .week: "This week"
        case .month: "This month"
        case .year: "This year"
        }
    }

    var comparisonTitle: LocalizedStringKey {
        switch self {
        case .week: "vs the week before"
        case .month: "vs the month before"
        case .year: "vs the year before"
        }
    }

    var toDateComparisonTitle: LocalizedStringKey {
        switch self {
        case .week: "vs this point last week"
        case .month: "vs this point last month"
        case .year: "vs this point last year"
        }
    }

    /// A past period by name, e.g. "12–18 paź", "wrzesień 2026", "2025".
    func title(for start: Date) -> String {
        let locale = Formatters.appLocale
        switch self {
        case .week:
            let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
            return (start..<end).formatted(.interval.day().month(.abbreviated).locale(locale))
        case .month:
            return start.formatted(.dateTime.month(.wide).year().locale(locale))
        case .year:
            return start.formatted(.dateTime.year().locale(locale))
        }
    }

    var axisStride: Int {
        switch self {
        case .week: 4
        case .month: 3
        case .year: 1
        }
    }

    var axisFormat: Date.FormatStyle {
        switch self {
        case .week: .dateTime.day().month(.abbreviated)
        case .month: .dateTime.month(.abbreviated)
        case .year: .dateTime.year()
        }
    }
}

extension Activity {
    var summary: ActivitySummary {
        ActivitySummary(
            id: id,
            type: type,
            start: startDate,
            distance: distanceMeters,
            movingSeconds: movingSeconds,
            elapsedSeconds: elapsedSeconds,
            volumeKg: type == .gym ? totalVolumeKg : 0,
            elevationGain: elevationGainMeters
        )
    }
}
