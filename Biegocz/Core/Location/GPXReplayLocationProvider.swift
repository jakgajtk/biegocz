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

    /// While paused, the last position repeats once a second and the rest of
    /// the route is delayed by the pause.
    private var isHolding = false

    func sessionPaused(_ paused: Bool) {
        isHolding = paused
    }

    func locationUpdates(for activity: ActivityType) -> AsyncStream<RoutePoint> {
        let points = loadRoute(named: activity == .ride ? "SampleRide" : "SampleRun")

        return AsyncStream { continuation in
            let task = Task {
                guard let firstTime = points.first?.timestamp else {
                    continuation.finish()
                    return
                }
                var start = Date.now
                var index = 0
                var last: RoutePoint?
                while index < points.count, !Task.isCancelled {
                    if isHolding, var held = last {
                        try? await Task.sleep(for: .seconds(1))
                        start.addTimeInterval(1)
                        held.timestamp = .now
                        continuation.yield(held)
                        continue
                    }
                    let point = points[index]
                    let due = start.addingTimeInterval(point.timestamp.timeIntervalSince(firstTime))
                    let wait = due.timeIntervalSinceNow
                    if wait > 0 {
                        try? await Task.sleep(for: .seconds(wait))
                    }
                    if Task.isCancelled { break }
                    var replayed = point
                    replayed.timestamp = due
                    continuation.yield(replayed)
                    last = replayed
                    index += 1
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
