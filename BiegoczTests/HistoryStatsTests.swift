import Foundation
import Testing
@testable import Biegocz

struct HistoryStatsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday, as in Poland
        return calendar
    }()

    private func date(_ text: String) -> Date {
        try! Date(text + "T12:00:00Z", strategy: .iso8601)
    }

    private func run(_ day: String, km: Double, minutes: Double, climb: Double? = nil) -> ActivitySummary {
        ActivitySummary(id: UUID(), type: .run, start: date(day), distance: km * 1000, movingSeconds: minutes * 60, elapsedSeconds: minutes * 60, elevationGain: climb)
    }

    private func ride(_ day: String, km: Double, minutes: Double) -> ActivitySummary {
        ActivitySummary(id: UUID(), type: .ride, start: date(day), distance: km * 1000, movingSeconds: minutes * 60, elapsedSeconds: minutes * 60)
    }

    private func gym(_ day: String, volume: Double, minutes: Double = 60) -> ActivitySummary {
        ActivitySummary(id: UUID(), type: .gym, start: date(day), elapsedSeconds: minutes * 60, volumeKg: volume)
    }

    @Test func monthlyBucketsIncludeEmptyMonthsOldestFirst() {
        let activities = [
            run("2026-10-03", km: 5, minutes: 30),
            run("2026-10-18", km: 10, minutes: 55),
            gym("2026-10-19", volume: 5_000, minutes: 70),
            ride("2026-08-20", km: 40, minutes: 90),
            run("2025-01-01", km: 3, minutes: 20), // too old for the chart
        ]
        let buckets = HistoryStats.buckets(activities, period: .month, count: 3, now: date("2026-10-20"), calendar: calendar)
        #expect(buckets.map(\.start) == [date("2026-08-01"), date("2026-09-01"), date("2026-10-01")].map { calendar.startOfDay(for: $0) })
        #expect(buckets.map(\.count) == [1, 0, 3])
        #expect(buckets[2].distance == 15_000)
        #expect(buckets[2].activeSeconds == (30 + 55 + 70) * 60)
        #expect(buckets[2].volumeKg == 5_000)
        #expect(buckets[2].countByType == [.run: 2, .gym: 1])
        #expect(buckets[0].distanceByType[.ride] == 40_000)
    }

    @Test func weeksStartOnMonday() {
        // Sunday 2026-10-18 and Monday 2026-10-19 are in different weeks.
        let activities = [run("2026-10-18", km: 5, minutes: 30), run("2026-10-19", km: 6, minutes: 35)]
        let buckets = HistoryStats.buckets(activities, period: .week, count: 2, now: date("2026-10-20"), calendar: calendar)
        #expect(buckets.map(\.distance) == [5_000, 6_000])
    }

    @Test func previousPeriodUpToTheSamePoint() throws {
        let activities = [
            run("2026-09-05", km: 5, minutes: 30),
            run("2026-09-19", km: 6, minutes: 35),
            run("2026-09-25", km: 10, minutes: 60), // after Sept 20: not compared yet
            run("2026-10-03", km: 7, minutes: 40),
        ]
        let previous = try #require(HistoryStats.previousToDate(activities, period: .month, now: date("2026-10-20"), calendar: calendar))
        #expect(previous.count == 2)
        #expect(previous.distance == 11_000)
    }

    @Test func changeAgainstThePreviousPeriod() {
        #expect(HistoryStats.change(from: 10, to: 15) == 0.5)
        #expect(HistoryStats.change(from: 10, to: 5) == -0.5)
        #expect(HistoryStats.change(from: 0, to: 5) == nil)
    }

    @Test func personalRecords() {
        let longRun = run("2026-09-01", km: 21.1, minutes: 120, climb: 80)
        let fastRun = run("2026-09-10", km: 5, minutes: 22) // 4:24 /km
        let shortSprint = run("2026-09-12", km: 2, minutes: 7) // faster, but too short
        let longRide = ride("2026-09-05", km: 80, minutes: 200)
        let fastRide = ride("2026-09-06", km: 20, minutes: 36) // 33,3 km/h
        let bigDay = gym("2026-09-07", volume: 12_000)
        let records = HistoryStats.records([longRun, fastRun, shortSprint, longRide, fastRide, bigDay, gym("2026-09-08", volume: 9_000)])
        let byKind = Dictionary(uniqueKeysWithValues: records.map { ($0.kind, $0) })

        #expect(byKind[.longestRun]?.activityID == longRun.id)
        #expect(byKind[.fastestRun]?.activityID == fastRun.id)
        #expect(abs((byKind[.fastestRun]?.value ?? 0) - 264) < 0.001)
        #expect(byKind[.longestRide]?.activityID == longRide.id)
        #expect(byKind[.fastestRide]?.activityID == fastRide.id)
        #expect(byKind[.biggestClimb]?.value == 80)
        #expect(byKind[.biggestGymVolume]?.activityID == bigDay.id)
    }

    @Test func noRecordsWithoutQualifyingActivities() {
        #expect(HistoryStats.records([run("2026-09-12", km: 2, minutes: 10)]).map(\.kind) == [.longestRun])
        #expect(HistoryStats.records([]).isEmpty)
    }

    @Test func weekStreak() {
        let now = date("2026-10-21") // Wednesday
        let lastThreeWeeks = [run("2026-10-07", km: 5, minutes: 30), gym("2026-10-13", volume: 1), run("2026-10-20", km: 5, minutes: 30)]
        #expect(HistoryStats.weekStreak(lastThreeWeeks, now: now, calendar: calendar) == 3)
        // Nothing yet this week: the streak still stands.
        #expect(HistoryStats.weekStreak(Array(lastThreeWeeks.dropLast()), now: now, calendar: calendar) == 2)
        // A gap breaks it.
        #expect(HistoryStats.weekStreak([run("2026-10-07", km: 5, minutes: 30), run("2026-10-20", km: 5, minutes: 30)], now: now, calendar: calendar) == 1)
        #expect(HistoryStats.weekStreak([], now: now, calendar: calendar) == 0)
    }
}
