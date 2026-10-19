import Foundation
import SwiftData

/// Saves finished activities to Health exactly once.
@MainActor
enum HealthSync {
    static func record(for activity: Activity) -> WorkoutRecord {
        WorkoutRecord(
            type: activity.type,
            start: activity.startDate,
            end: activity.endDate ?? activity.startDate.addingTimeInterval(activity.elapsedSeconds),
            segments: activity.routeSegments
        )
    }

    /// Saves `activity` unless it's already in Health. Uses the live workout
    /// when there is one. Failure (no access, Health unavailable) is silent:
    /// the activity is safe in the app either way.
    static func save(
        _ activity: Activity,
        using health: any HealthStore,
        live: (any LiveWorkout)? = nil,
        context: ModelContext
    ) async {
        guard activity.isFinished, activity.healthKitWorkoutID == nil else {
            live?.discard()
            return
        }
        await health.requestAuthorization()
        let record = record(for: activity)
        do {
            let id: UUID
            if let live {
                id = try await live.finish(record)
            } else {
                id = try await health.saveWorkout(record)
            }
            activity.healthKitWorkoutID = id
            try? context.save()
        } catch {
            // Not saved to Health; nothing else to do.
        }
    }
}
