import Foundation

/// Before a run or ride: asks for location access and shows GPS quality.
@MainActor
@Observable
final class PreStartModel {
    let type: ActivityType
    private(set) var authorization: LocationAuthorization
    private(set) var quality = GPSQuality.none
    /// Latest position, where suggested routes start.
    private(set) var position: Coordinate?
    /// The route picked from the suggestions, shown during the run or ride.
    var plannedRoute: SuggestedRoute?

    private let location: any LocationProvider
    private let health: any HealthStore
    private var task: Task<Void, Never>?

    init(type: ActivityType, location: any LocationProvider, health: any HealthStore) {
        self.type = type
        self.location = location
        self.health = health
        self.authorization = location.authorization
    }

    func start() async {
        authorization = await location.requestAuthorization()
        // First time a run or ride starts is when Health access is first needed.
        await health.requestAuthorization()
        guard authorization == .authorized, task == nil else { return }
        let updates = location.locationUpdates(for: type)
        task = Task { [weak self] in
            for await point in updates {
                self?.quality = GPSQuality(horizontalAccuracy: point.horizontalAccuracy)
                if point.horizontalAccuracy >= 0 {
                    self?.position = Coordinate(latitude: point.latitude, longitude: point.longitude)
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
