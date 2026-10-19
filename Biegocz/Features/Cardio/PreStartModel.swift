import Foundation

/// Before a run or ride: asks for location access and shows GPS quality.
@MainActor
@Observable
final class PreStartModel {
    let type: ActivityType
    private(set) var authorization: LocationAuthorization
    private(set) var quality = GPSQuality.none

    private let location: any LocationProvider
    private var task: Task<Void, Never>?

    init(type: ActivityType, location: any LocationProvider) {
        self.type = type
        self.location = location
        self.authorization = location.authorization
    }

    func start() async {
        authorization = await location.requestAuthorization()
        guard authorization == .authorized, task == nil else { return }
        let updates = location.locationUpdates(for: type)
        task = Task { [weak self] in
            for await point in updates {
                self?.quality = GPSQuality(horizontalAccuracy: point.horizontalAccuracy)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
