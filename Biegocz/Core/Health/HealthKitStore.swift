import HealthKit

@MainActor
final class HealthKitStore: HealthStore {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        let types: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
        ]
        try await store.requestAuthorization(toShare: types, read: types)
    }
}
