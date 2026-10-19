import Foundation

/// Replays a bundled GPX route in real time, so the live run screen can be
/// tested in the simulator. Timestamps are shifted to start now.
@MainActor
final class GPXReplayLocationProvider: LocationProvider {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    var authorization: LocationAuthorization { .authorized }

    func requestAuthorization() async -> LocationAuthorization { .authorized }

    func locationUpdates(for activity: ActivityType) -> AsyncStream<RoutePoint> {
        let points = loadRoute(named: activity == .ride ? "SampleRide" : "SampleRun")

        return AsyncStream { continuation in
            let task = Task {
                guard let firstTime = points.first?.timestamp else {
                    continuation.finish()
                    return
                }
                let start = Date.now
                for point in points {
                    let offset = point.timestamp.timeIntervalSince(firstTime)
                    let due = start.addingTimeInterval(offset)
                    let wait = due.timeIntervalSinceNow
                    if wait > 0 {
                        try? await Task.sleep(for: .seconds(wait))
                    }
                    if Task.isCancelled { break }
                    var replayed = point
                    replayed.timestamp = due
                    continuation.yield(replayed)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func loadRoute(named name: String) -> [RoutePoint] {
        guard let url = bundle.url(forResource: name, withExtension: "gpx"),
              let data = try? Data(contentsOf: url)
        else { return [] }
        return (try? GPXParser.parse(data)) ?? []
    }
}
