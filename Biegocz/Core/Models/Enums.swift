import Foundation

enum ActivityType: String, Codable, CaseIterable, Identifiable, Sendable {
    case gym
    case run
    case ride

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .gym: "Gym"
        case .run: "Run"
        case .ride: "Ride"
        }
    }

    var systemImage: String {
        switch self {
        case .gym: "figure.strengthtraining.traditional"
        case .run: "figure.run"
        case .ride: "figure.outdoor.cycle"
        }
    }

    var isCardio: Bool { self != .gym }
}

enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case chest
    case back
    case legs
    case shoulders
    case arms
    case core

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .chest: "Chest"
        case .back: "Back"
        case .legs: "Legs"
        case .shoulders: "Shoulders"
        case .arms: "Arms"
        case .core: "Core"
        }
    }
}

enum LoggingType: String, Codable, CaseIterable, Identifiable, Sendable {
    case weightReps
    case bodyweightReps
    case duration

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .weightReps: "Weight and reps"
        case .bodyweightReps: "Bodyweight reps"
        case .duration: "Time"
        }
    }
}
