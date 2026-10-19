import CoreLocation
import HealthKit

/// HealthKit on iPhone. Runs and rides use `HKWorkoutSession` with its
/// `HKLiveWorkoutBuilder` (iOS 26). The builder's own distance collection
/// is turned off and distance samples come from our filtered GPS, so Health
/// shows exactly the distance the app shows, and nothing is counted twice.
@MainActor
final class HealthKitStore: HealthStore {
    private let store = HKHealthStore()
    private var didRequestAuthorization = false

    private static let shareTypes: Set<HKSampleType> = [
        HKObjectType.workoutType(),
        HKSeriesType.workoutRoute(),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.distanceCycling),
    ]

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    var canSaveWorkouts: Bool {
        isAvailable && store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    func requestAuthorization() async {
        guard isAvailable, !didRequestAuthorization else { return }
        didRequestAuthorization = true
        // Only prompts the first time; denial isn't reported as an error.
        try? await store.requestAuthorization(toShare: Self.shareTypes, read: [])
    }

    func startLiveWorkout(_ type: ActivityType, at start: Date) async -> (any LiveWorkout)? {
        guard canSaveWorkouts, type.isCardio else { return nil }
        let configuration = Self.configuration(for: type)
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            let dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            dataSource.disableCollection(for: Self.distanceType(for: type))
            builder.dataSource = dataSource
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            return HealthKitLiveWorkout(store: store, session: session, builder: builder, type: type)
        } catch {
            return nil
        }
    }

    func saveWorkout(_ record: WorkoutRecord) async throws -> UUID {
        guard canSaveWorkouts else { throw HealthError.notAuthorized }
        let builder = HKWorkoutBuilder(healthStore: store, configuration: Self.configuration(for: record.type), device: .local())
        try await builder.beginCollection(at: record.start)
        if record.type.isCardio {
            let pauses = RouteSummaries.pauses(between: record.segments).flatMap { pause in
                [
                    HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: pause.start, duration: 0), metadata: nil),
                    HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: pause.end, duration: 0), metadata: nil),
                ]
            }
            if !pauses.isEmpty {
                try await builder.addWorkoutEvents(pauses)
            }
            let samples = Self.distanceSamples(for: record)
            if !samples.isEmpty {
                try await builder.addSamples(samples)
            }
        }
        try await builder.endCollection(at: record.end)
        guard let workout = try await builder.finishWorkout() else { throw HealthError.unavailable }
        if record.type.isCardio {
            try? await Self.saveRoute(record.segments, for: workout, in: store)
        }
        return workout.uuid
    }

    func endAbandonedLiveWorkout() async {
        guard isAvailable else { return }
        // A session recovered after a crash is ended and its builder discarded;
        // the activity is then saved from our own persisted data instead.
        guard let session = try? await store.recoverActiveWorkoutSession() else { return }
        session.associatedWorkoutBuilder().discardWorkout()
        session.end()
    }

    // MARK: Helpers

    static func configuration(for type: ActivityType) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        switch type {
        case .run:
            configuration.activityType = .running
            configuration.locationType = .outdoor
        case .ride:
            configuration.activityType = .cycling
            configuration.locationType = .outdoor
        case .gym:
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .indoor
        }
        return configuration
    }

    static func distanceType(for type: ActivityType) -> HKQuantityType {
        type == .ride ? HKQuantityType(.distanceCycling) : HKQuantityType(.distanceWalkingRunning)
    }

    static func distanceSamples(for record: WorkoutRecord) -> [HKSample] {
        let quantityType = distanceType(for: record.type)
        return RouteSummaries.distanceChunks(of: record.segments).map { chunk in
            HKCumulativeQuantitySample(
                type: quantityType,
                quantity: HKQuantity(unit: .meter(), doubleValue: chunk.meters),
                start: chunk.start,
                end: chunk.end
            )
        }
    }

    static func saveRoute(_ segments: [[RoutePoint]], for workout: HKWorkout, in store: HKHealthStore) async throws {
        let locations = segments.flatMap { $0 }.map { point in
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
                altitude: point.altitude,
                horizontalAccuracy: point.horizontalAccuracy,
                verticalAccuracy: -1,
                timestamp: point.timestamp
            )
        }
        guard !locations.isEmpty else { return }
        let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
        try await routeBuilder.insertRouteData(locations)
        _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
    }
}

@MainActor
final class HealthKitLiveWorkout: LiveWorkout {
    private let store: HKHealthStore
    private let session: HKWorkoutSession
    private let builder: HKLiveWorkoutBuilder
    private let type: ActivityType

    init(store: HKHealthStore, session: HKWorkoutSession, builder: HKLiveWorkoutBuilder, type: ActivityType) {
        self.store = store
        self.session = session
        self.builder = builder
        self.type = type
    }

    func pause(at date: Date) {
        session.pause()
    }

    func resume(at date: Date) {
        session.resume()
    }

    func finish(_ record: WorkoutRecord) async throws -> UUID {
        let samples = HealthKitStore.distanceSamples(for: record)
        if !samples.isEmpty {
            try await builder.addSamples(samples)
        }
        session.stopActivity(with: record.end)
        try await builder.endCollection(at: record.end)
        let workout = try await builder.finishWorkout()
        session.end()
        guard let workout else { throw HealthError.unavailable }
        try? await HealthKitStore.saveRoute(record.segments, for: workout, in: store)
        return workout.uuid
    }

    func discard() {
        builder.discardWorkout()
        session.end()
    }
}
