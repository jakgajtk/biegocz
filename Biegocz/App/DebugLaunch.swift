#if DEBUG
import Foundation
import SwiftData
import SwiftUI

/// Debug-only launch arguments for checking screens in the simulator:
///
///     xcrun simctl launch booted com.gajtkowski.biegocz -demoData YES -screen gym
///
/// `-demoData YES` uses an in-memory store filled with sample history, so the
/// real store is never touched. `-screen` opens one screen directly.
enum DebugLaunch {
    enum Screen: String {
        case history, exercises, settings
        case gym, picker, summary
        case exerciseDetail
        case activityDetail
        case prestart, run, ride
    }

    static var usesDemoData: Bool {
        UserDefaults.standard.bool(forKey: "demoData")
    }

    static var screen: Screen? {
        UserDefaults.standard.string(forKey: "screen").flatMap(Screen.init(rawValue:))
    }

    @MainActor
    static func makeDemoContainer() -> ModelContainer {
        let container = try! PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        try! ExerciseSeeder.seedIfNeeded(in: context)
        DemoData.insert(into: context)
        return container
    }
}

@MainActor
enum DemoData {
    static func exercise(_ key: String, in context: ModelContext) -> Exercise {
        let all = try! context.fetch(FetchDescriptor<Exercise>())
        return all.first { $0.builtInKey == key }!
    }

    static func insert(into context: ModelContext) {
        let bench = exercise("bench_press", in: context)
        let squat = exercise("back_squat", in: context)
        let pullUp = exercise("pull_up", in: context)
        let plank = exercise("plank", in: context)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        // Eight weeks of progressing workouts, twice a week.
        for week in 0..<8 {
            for day in [1, 4] {
                let daysAgo = (7 - week) * 7 + (7 - day)
                guard daysAgo > 0 else { continue }
                let start = calendar.date(byAdding: .day, value: -daysAgo, to: today)!.addingTimeInterval(18 * 3600)
                let activity = Activity(type: .gym, startDate: start)
                context.insert(activity)
                let progress = Double(week) * 2.5
                add(bench, to: activity, order: 0, sets: Array(repeating: SetValues(weightKg: 70 + progress, reps: 8), count: 3), start: start)
                add(squat, to: activity, order: 1, sets: [
                    SetValues(weightKg: 90 + progress, reps: 5),
                    SetValues(weightKg: 95 + progress, reps: 5),
                    SetValues(weightKg: 100 + progress, reps: 3),
                ], start: start)
                add(pullUp, to: activity, order: 2, sets: Array(repeating: SetValues(reps: 6 + week / 2), count: 3), start: start)
                add(plank, to: activity, order: 3, sets: [SetValues(durationSeconds: 60)], start: start)
                activity.elapsedSeconds = 3_900
                activity.movingSeconds = 3_900
                activity.endDate = start.addingTimeInterval(3_900)
                activity.isFinished = true
            }
        }

        // A run yesterday and a ride two days ago, from the sample routes.
        insertCardio(.run, route: "SampleRun", daysAgo: 1, into: context)
        insertCardio(.ride, route: "SampleRide", daysAgo: 2, into: context)
        try? context.save()
    }

    private static func insertCardio(_ type: ActivityType, route: String, daysAgo: Int, into context: ModelContext) {
        guard let url = Bundle.main.url(forResource: route, withExtension: "gpx"),
              let data = try? Data(contentsOf: url),
              let points = try? GPXParser.parse(data),
              let first = points.first, let last = points.last
        else { return }
        let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        let shift = start.timeIntervalSince(first.timestamp)
        var engine = CardioEngine(activityType: type, startDate: start)
        for point in points {
            var shifted = point
            shifted.timestamp = point.timestamp.addingTimeInterval(shift)
            engine.ingest(shifted, receivedAt: shifted.timestamp)
        }
        let end = last.timestamp.addingTimeInterval(shift)
        let activity = Activity(type: type, startDate: start)
        activity.endDate = end
        activity.elapsedSeconds = engine.elapsedTime(at: end)
        activity.movingSeconds = engine.movingTime(at: end)
        activity.distanceMeters = engine.distance
        activity.elevationGainMeters = engine.elevationGain
        activity.routeData = RouteCodec.encode(segments: engine.segments)
        activity.isFinished = true
        context.insert(activity)
    }

    private static func add(_ exercise: Exercise, to activity: Activity, order: Int, sets: [SetValues], start: Date) {
        let entry = WorkoutExercise(exercise: exercise, order: order)
        activity.exercises.append(entry)
        for (index, values) in sets.enumerated() {
            let set = ExerciseSet(order: index, values: values)
            set.isDone = true
            set.completedAt = start.addingTimeInterval(Double(order * 600 + index * 150))
            entry.sets.append(set)
        }
    }
}
#endif
