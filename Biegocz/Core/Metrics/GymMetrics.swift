import Foundation

/// The values of one set, independent of SwiftData.
struct SetValues: Equatable, Codable, Sendable {
    var weightKg: Double?
    var reps: Int?
    var durationSeconds: Double?

    static let empty = SetValues()
}

/// A set as logged in some past session.
struct LoggedSet: Equatable, Sendable {
    var values: SetValues
    var isDone: Bool
}

/// One past session of a single exercise.
struct ExerciseSession: Equatable, Sendable {
    var date: Date
    var sets: [LoggedSet]

    var doneSets: [SetValues] { sets.filter(\.isDone).map(\.values) }
}

enum OneRepMax {
    static let validReps = 1...12

    /// Epley estimate, `w × (1 + reps / 30)`. Only for 1 to 12 reps with a positive weight.
    static func epley(weightKg: Double?, reps: Int?) -> Double? {
        guard let weightKg, let reps, weightKg > 0, validReps.contains(reps) else { return nil }
        return weightKg * (1 + Double(reps) / 30)
    }

    /// The set with the highest estimated 1RM, with that estimate.
    static func bestSet(in sets: [SetValues]) -> (set: SetValues, e1RM: Double)? {
        sets
            .compactMap { set in epley(weightKg: set.weightKg, reps: set.reps).map { (set, $0) } }
            .max { $0.1 < $1.1 }
    }

    /// Best e1RM of each session that has a qualifying set, oldest first.
    static func bestPerSession(_ sessions: [ExerciseSession]) -> [(date: Date, e1RM: Double)] {
        sessions
            .compactMap { session in bestSet(in: session.doneSets).map { (session.date, $0.e1RM) } }
            .sorted { $0.0 < $1.0 }
    }
}

enum SetPrefill {
    /// A new set copies the previous set in this session. The first set of an
    /// exercise copies the first set of the last session that included it.
    static func values(previousInSession: SetValues?, lastSession: ExerciseSession?) -> SetValues {
        if let previousInSession { return previousInSession }
        if let first = lastSession?.doneSets.first ?? lastSession?.sets.first?.values { return first }
        return .empty
    }

    /// Values for set number `index` (0-based) when repeating a past session:
    /// that session's set at the same position, or its last set if it had fewer.
    static func repeated(from session: ExerciseSession, index: Int) -> SetValues {
        guard !session.sets.isEmpty else { return .empty }
        return session.sets[min(index, session.sets.count - 1)].values
    }
}

enum WeightStepper {
    /// Adds or removes one step, never going below zero, and snaps to the
    /// step grid so free-typed values like 81 become 82.5 / 80.
    static func step(_ weight: Double?, by step: Double, up: Bool) -> Double {
        let current = weight ?? 0
        guard step > 0 else { return current }
        let ratio = current / step
        let snapped = up ? (ratio + 1e-9).rounded(.down) + 1 : (ratio - 1e-9).rounded(.up) - 1
        return max(0, (snapped * step * 1000).rounded() / 1000)
    }
}

/// "3 × 8 @ 80 kg" when every done set was the same, else the sets one by one.
enum LastTimeSummary: Equatable {
    case uniform(count: Int, values: SetValues)
    case varied([SetValues])

    init?(session: ExerciseSession) {
        let sets = session.doneSets
        guard let first = sets.first else { return nil }
        if sets.allSatisfy({ $0 == first }) {
            self = .uniform(count: sets.count, values: first)
        } else {
            self = .varied(sets)
        }
    }
}

/// Rest countdown between sets. Pure: the caller supplies `now`.
struct RestTimer: Equatable, Sendable {
    private(set) var endDate: Date

    init(duration: TimeInterval, startingAt start: Date) {
        endDate = start.addingTimeInterval(duration)
    }

    func remaining(at now: Date) -> TimeInterval {
        max(0, endDate.timeIntervalSince(now))
    }

    func isFinished(at now: Date) -> Bool {
        remaining(at: now) <= 0
    }

    /// Adds time; if the timer already ran out, counts from now.
    mutating func extend(by seconds: TimeInterval, now: Date) {
        endDate = max(endDate, now).addingTimeInterval(seconds)
    }
}
