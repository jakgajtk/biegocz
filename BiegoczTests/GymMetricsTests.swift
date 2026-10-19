import Foundation
import Testing
@testable import Biegocz

private func approx(_ a: Double?, _ b: Double) -> Bool {
    guard let a else { return false }
    return abs(a - b) < 0.0001
}

struct OneRepMaxTests {
    @Test func epleyFormula() {
        // 100 × (1 + 5/30) = 116.67
        #expect(approx(OneRepMax.epley(weightKg: 100, reps: 5), 116.666_666))
        #expect(approx(OneRepMax.epley(weightKg: 60, reps: 1), 62))
        #expect(approx(OneRepMax.epley(weightKg: 90, reps: 12), 126))
    }

    @Test(arguments: [0, 13, 20])
    func repsOutsideOneToTwelveAreIgnored(reps: Int) {
        #expect(OneRepMax.epley(weightKg: 100, reps: reps) == nil)
    }

    @Test func missingOrZeroWeightIsIgnored() {
        #expect(OneRepMax.epley(weightKg: nil, reps: 5) == nil)
        #expect(OneRepMax.epley(weightKg: 0, reps: 5) == nil)
        #expect(OneRepMax.epley(weightKg: 100, reps: nil) == nil)
    }

    @Test func bestSetPicksHighestEstimateNotHeaviestWeight() throws {
        let sets = [
            SetValues(weightKg: 100, reps: 1),  // 103.3
            SetValues(weightKg: 90, reps: 6),   // 108
            SetValues(weightKg: 60, reps: 20),  // ignored: > 12 reps
        ]
        let best = try #require(OneRepMax.bestSet(in: sets))
        #expect(best.set == SetValues(weightKg: 90, reps: 6))
        #expect(approx(best.e1RM, 108))
    }

    @Test func bestPerSessionIsSortedAndSkipsSessionsWithoutQualifyingSets() {
        let day = 86_400.0
        let sessions = [
            ExerciseSession(date: Date(timeIntervalSince1970: 3 * day), sets: [
                LoggedSet(values: SetValues(weightKg: 100, reps: 3), isDone: true),
            ]),
            ExerciseSession(date: Date(timeIntervalSince1970: 1 * day), sets: [
                LoggedSet(values: SetValues(weightKg: 90, reps: 3), isDone: true),
                LoggedSet(values: SetValues(weightKg: 200, reps: 3), isDone: false), // not done
            ]),
            ExerciseSession(date: Date(timeIntervalSince1970: 2 * day), sets: [
                LoggedSet(values: SetValues(weightKg: 50, reps: 30), isDone: true),
            ]),
        ]
        let points = OneRepMax.bestPerSession(sessions)
        #expect(points.map(\.date) == [Date(timeIntervalSince1970: day), Date(timeIntervalSince1970: 3 * day)])
        #expect(points.count == 2)
        #expect(approx(points.first?.e1RM, 99))
        #expect(approx(points.last?.e1RM, 110))
    }
}

struct SetPrefillTests {
    private let lastSession = ExerciseSession(date: .now, sets: [
        LoggedSet(values: SetValues(weightKg: 80, reps: 8), isDone: true),
        LoggedSet(values: SetValues(weightKg: 85, reps: 6), isDone: true),
    ])

    @Test func newSetCopiesPreviousSetInSession() {
        let previous = SetValues(weightKg: 82.5, reps: 7)
        #expect(SetPrefill.values(previousInSession: previous, lastSession: lastSession) == previous)
    }

    @Test func firstSetCopiesFirstSetOfLastSession() {
        #expect(SetPrefill.values(previousInSession: nil, lastSession: lastSession) == SetValues(weightKg: 80, reps: 8))
    }

    @Test func firstSetPrefersDoneSetsOfLastSession() {
        let session = ExerciseSession(date: .now, sets: [
            LoggedSet(values: SetValues(weightKg: 40, reps: 10), isDone: false),
            LoggedSet(values: SetValues(weightKg: 60, reps: 5), isDone: true),
        ])
        #expect(SetPrefill.values(previousInSession: nil, lastSession: session) == SetValues(weightKg: 60, reps: 5))
    }

    @Test func noHistoryGivesEmptySet() {
        #expect(SetPrefill.values(previousInSession: nil, lastSession: nil) == .empty)
    }

    @Test func repeatCopiesSetAtSamePosition() {
        #expect(SetPrefill.repeated(from: lastSession, index: 1) == SetValues(weightKg: 85, reps: 6))
        #expect(SetPrefill.repeated(from: lastSession, index: 5) == SetValues(weightKg: 85, reps: 6))
    }
}

struct WeightStepperTests {
    @Test func stepsOnGrid() {
        #expect(WeightStepper.step(80, by: 2.5, up: true) == 82.5)
        #expect(WeightStepper.step(80, by: 2.5, up: false) == 77.5)
        #expect(WeightStepper.step(nil, by: 2.5, up: true) == 2.5)
    }

    @Test func snapsFreeEntryToGrid() {
        #expect(WeightStepper.step(81, by: 2.5, up: true) == 82.5)
        #expect(WeightStepper.step(81, by: 2.5, up: false) == 80)
        #expect(WeightStepper.step(11.3, by: 1.25, up: true) == 12.5)
    }

    @Test func neverGoesBelowZero() {
        #expect(WeightStepper.step(0, by: 2.5, up: false) == 0)
        #expect(WeightStepper.step(1, by: 2.5, up: false) == 0)
    }
}

struct LastTimeSummaryTests {
    @Test func uniformSets() {
        let session = ExerciseSession(date: .now, sets: Array(repeating: LoggedSet(values: SetValues(weightKg: 80, reps: 8), isDone: true), count: 3))
        #expect(LastTimeSummary(session: session) == .uniform(count: 3, values: SetValues(weightKg: 80, reps: 8)))
    }

    @Test func variedSetsIgnoreUndone() {
        let session = ExerciseSession(date: .now, sets: [
            LoggedSet(values: SetValues(weightKg: 80, reps: 8), isDone: true),
            LoggedSet(values: SetValues(weightKg: 85, reps: 6), isDone: true),
            LoggedSet(values: SetValues(weightKg: 90, reps: 1), isDone: false),
        ])
        #expect(LastTimeSummary(session: session) == .varied([SetValues(weightKg: 80, reps: 8), SetValues(weightKg: 85, reps: 6)]))
    }

    @Test func noDoneSetsMeansNoSummary() {
        let session = ExerciseSession(date: .now, sets: [LoggedSet(values: SetValues(weightKg: 80, reps: 8), isDone: false)])
        #expect(LastTimeSummary(session: session) == nil)
    }

    @Test func polishText() {
        let bundle = TestSupport.bundle(for: "pl")
        let text = LastTimeFormatting.text(
            for: .uniform(count: 3, values: SetValues(weightKg: 82.5, reps: 8)),
            loggingType: .weightReps, bundle: bundle, locale: TestSupport.polish
        )
        #expect(TestSupport.normalizingSpaces(text) == "Ostatnio: 3 × 8, 82,5 kg")
    }

    @Test func englishText() {
        let bundle = TestSupport.bundle(for: "en")
        let text = LastTimeFormatting.text(
            for: .uniform(count: 3, values: SetValues(weightKg: 80, reps: 8)),
            loggingType: .weightReps, bundle: bundle, locale: TestSupport.english
        )
        #expect(TestSupport.normalizingSpaces(text) == "Last time: 3 × 8 @ 80 kg")
    }
}

struct RestTimerTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test func countsDown() {
        let timer = RestTimer(duration: 120, startingAt: start)
        #expect(timer.remaining(at: start.addingTimeInterval(30)) == 90)
        #expect(timer.remaining(at: start.addingTimeInterval(200)) == 0)
        #expect(timer.isFinished(at: start.addingTimeInterval(120)))
    }

    @Test func extendAddsThirtySeconds() {
        var timer = RestTimer(duration: 120, startingAt: start)
        timer.extend(by: 30, now: start.addingTimeInterval(10))
        #expect(timer.remaining(at: start.addingTimeInterval(10)) == 140)
    }

    @Test func extendAfterExpiryCountsFromNow() {
        var timer = RestTimer(duration: 120, startingAt: start)
        let later = start.addingTimeInterval(300)
        timer.extend(by: 30, now: later)
        #expect(timer.remaining(at: later) == 30)
    }
}
