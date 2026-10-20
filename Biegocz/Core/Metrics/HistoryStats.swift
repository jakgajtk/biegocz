import Foundation

/// The numbers of one finished activity that history statistics need.
struct ActivitySummary: Equatable, Sendable {
    var id: UUID
    var type: ActivityType
    var start: Date
    var distance: Double = 0
    var movingSeconds: Double = 0
    var elapsedSeconds: Double = 0
    var volumeKg: Double = 0
    var elevationGain: Double?

    /// Moving time for runs and rides, the whole session for the gym.
    var activeSeconds: Double {
        type.isCardio ? movingSeconds : elapsedSeconds
    }
}

enum StatsPeriod: String, CaseIterable, Identifiable, Sendable {
    case week, month, year

    var id: Self { self }

    var component: Calendar.Component {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    /// How many periods the chart shows.
    var chartCount: Int {
        switch self {
        case .week: 12
        case .month: 12
        case .year: 5
        }
    }
}

/// Totals for one week, month or year.
struct PeriodTotals: Equatable, Sendable {
    var start: Date
    var count = 0
    var distance = 0.0
    var activeSeconds = 0.0
    var volumeKg = 0.0
    var countByType: [ActivityType: Int] = [:]
    var distanceByType: [ActivityType: Double] = [:]
    var activeSecondsByType: [ActivityType: Double] = [:]

    mutating func add(_ activity: ActivitySummary) {
        count += 1
        distance += activity.distance
        activeSeconds += activity.activeSeconds
        volumeKg += activity.volumeKg
        countByType[activity.type, default: 0] += 1
        distanceByType[activity.type, default: 0] += activity.distance
        activeSecondsByType[activity.type, default: 0] += activity.activeSeconds
    }
}

/// A personal best, pointing at the activity that set it.
struct PersonalRecord: Equatable, Identifiable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case longestRun, fastestRun, longestRide, fastestRide, biggestClimb, biggestGymVolume
    }

    var kind: Kind
    var value: Double
    var activityID: UUID
    var date: Date

    var id: Kind { kind }
}

enum HistoryStats {
    /// Runs at least this long (meters) count for the fastest average pace.
    static let fastestRunMinimum = 5_000.0
    /// Rides at least this long (meters) count for the fastest average speed.
    static let fastestRideMinimum = 10_000.0

    /// The last `count` periods up to and including the one containing `now`,
    /// oldest first. Empty periods are included, so charts have no gaps.
    static func buckets(
        _ activities: [ActivitySummary],
        period: StatsPeriod,
        count: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> [PeriodTotals] {
        guard count > 0, let current = calendar.dateInterval(of: period.component, for: now)?.start else { return [] }
        let starts = (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: period.component, value: -offset, to: current)
        }
        var totals = starts.map { PeriodTotals(start: $0) }
        let index = Dictionary(uniqueKeysWithValues: starts.enumerated().map { ($1, $0) })
        for activity in activities {
            guard let start = calendar.dateInterval(of: period.component, for: activity.start)?.start,
                  let position = index[start]
            else { continue }
            totals[position].add(activity)
        }
        return totals
    }

    /// Totals of the period containing `date`.
    static func totals(
        _ activities: [ActivitySummary],
        period: StatsPeriod,
        containing date: Date,
        calendar: Calendar = .current
    ) -> PeriodTotals {
        buckets(activities, period: period, count: 1, now: date, calendar: calendar).first ?? PeriodTotals(start: date)
    }

    /// The previous period up to the same point as `now` in the current one,
    /// e.g. September 1–20 on October 20, for a fair comparison.
    static func previousToDate(
        _ activities: [ActivitySummary],
        period: StatsPeriod,
        now: Date,
        calendar: Calendar = .current
    ) -> PeriodTotals? {
        guard let current = calendar.dateInterval(of: period.component, for: now)?.start,
              let previous = calendar.date(byAdding: period.component, value: -1, to: current)
        else { return nil }
        let elapsed = now.timeIntervalSince(current)
        let end = min(previous.addingTimeInterval(elapsed), current)
        var totals = PeriodTotals(start: previous)
        for activity in activities where activity.start >= previous && activity.start < end {
            totals.add(activity)
        }
        return totals
    }

    /// Relative change from `previous` to `current`, e.g. 0.25 for +25%.
    /// `nil` when there's nothing to compare with.
    static func change(from previous: Double, to current: Double) -> Double? {
        guard previous > 0 else { return nil }
        return (current - previous) / previous
    }

    static func records(_ activities: [ActivitySummary]) -> [PersonalRecord] {
        let runs = activities.filter { $0.type == .run }
        let rides = activities.filter { $0.type == .ride }
        let gym = activities.filter { $0.type == .gym }
        var records: [PersonalRecord] = []

        func add(_ kind: PersonalRecord.Kind, _ candidates: [ActivitySummary], value: (ActivitySummary) -> Double?, lowerIsBetter: Bool = false) {
            let scored = candidates.compactMap { activity in value(activity).map { (activity, $0) } }
            let best = lowerIsBetter ? scored.min { $0.1 < $1.1 } : scored.max { $0.1 < $1.1 }
            if let (activity, score) = best {
                records.append(PersonalRecord(kind: kind, value: score, activityID: activity.id, date: activity.start))
            }
        }

        add(.longestRun, runs) { $0.distance > 0 ? $0.distance : nil }
        // Seconds per kilometer: lower is better.
        add(.fastestRun, runs, value: { run in
            guard run.distance >= fastestRunMinimum, run.movingSeconds > 0 else { return nil }
            return run.movingSeconds / run.distance * 1000
        }, lowerIsBetter: true)
        add(.longestRide, rides) { $0.distance > 0 ? $0.distance : nil }
        add(.fastestRide, rides) { ride in
            guard ride.distance >= fastestRideMinimum, ride.movingSeconds > 0 else { return nil }
            return ride.distance / ride.movingSeconds
        }
        add(.biggestClimb, runs + rides) { activity in
            activity.elevationGain.flatMap { $0 > 0 ? $0 : nil }
        }
        add(.biggestGymVolume, gym) { $0.volumeKg > 0 ? $0.volumeKg : nil }
        return records
    }

    /// Weeks in a row with at least one activity, ending this week. A week
    /// without activities yet doesn't break the streak until it's over.
    static func weekStreak(_ activities: [ActivitySummary], now: Date, calendar: Calendar = .current) -> Int {
        let activeWeeks = Set(activities.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.start)?.start })
        guard var week = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        if !activeWeeks.contains(week) {
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { return 0 }
            week = previous
        }
        var streak = 0
        while activeWeeks.contains(week) {
            streak += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { break }
            week = previous
        }
        return streak
    }
}
