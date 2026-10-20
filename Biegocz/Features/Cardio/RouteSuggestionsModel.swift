import Foundation

/// A round trip offered before a run or ride.
struct SuggestedRoute: Identifiable, Equatable, Sendable {
    /// Position among the suggestions, also the direction it heads out in.
    let id: Int
    /// Direction of the loop from the start, degrees clockwise from north.
    var bearing: Double
    var coordinates: [Coordinate]
    var distance: Double
}

/// Finds three loops of about the chosen length from the current position,
/// heading out in different directions.
@MainActor
@Observable
final class RouteSuggestionsModel: Identifiable {
    static let count = 3

    let type: ActivityType
    let start: Coordinate
    private(set) var targetDistance: Double
    private(set) var routes: [SuggestedRoute] = []
    private(set) var isLoading = false
    /// Nothing could be planned (offline, or no roads around).
    private(set) var failed = false
    /// Apple Maps asked for a break; planning resumes on its own.
    private(set) var isThrottled = false
    var selectedID: Int?
    /// How long to wait after Apple Maps throttles before asking again.
    let throttleWait: Duration

    private let directions: any DirectionsProvider
    private var bearingOffset: Double
    private var task: Task<Void, Never>?
    /// Finished suggestions per target distance, so going back to a distance
    /// is instant and costs no requests. Cleared by `shuffle`.
    private var cache: [Double: [SuggestedRoute]] = [:]
    /// Quick taps through the distances only plan the last one.
    static let debounce: Duration = .milliseconds(350)

    init(
        type: ActivityType,
        start: Coordinate,
        directions: any DirectionsProvider,
        bearingOffset: Double = 0,
        throttleWait: Duration = .seconds(20)
    ) {
        self.type = type
        self.start = start
        self.directions = directions
        self.bearingOffset = bearingOffset
        self.throttleWait = throttleWait
        self.targetDistance = Self.defaultDistance(for: type)
    }

    /// Distance presets in kilometers.
    static func presets(for type: ActivityType) -> [Double] {
        type == .ride ? [10, 20, 30, 50, 80] : [3, 5, 8, 10, 15, 21.1]
    }

    static func defaultDistance(for type: ActivityType) -> Double {
        type == .ride ? 20_000 : 5_000
    }

    var selected: SuggestedRoute? {
        routes.first { $0.id == selectedID }
    }

    func setTarget(_ meters: Double) {
        guard meters != targetDistance else { return }
        targetDistance = meters
        load(after: Self.debounce)
    }

    /// New directions for the same distance.
    func shuffle() {
        bearingOffset = (bearingOffset + 360 / Double(Self.count) / 2).truncatingRemainder(dividingBy: 360)
        cache = [:]
        load()
    }

    func load(after delay: Duration = .zero) {
        task?.cancel()
        selectedID = nil
        failed = false
        if let cached = cache[targetDistance] {
            routes = cached
            selectedID = cached.first?.id
            isLoading = false
            isThrottled = false
            return
        }
        routes = []
        isLoading = true
        isThrottled = false
        let bearings = LoopPlanner.bearings(count: Self.count, offset: bearingOffset)
        let (start, target, type, directions) = (start, targetDistance, type, directions)
        task = Task {
            if delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            var throttled = false
            while true {
                throttled = false
                await withTaskGroup(of: Plan.self) { group in
                    for (index, bearing) in bearings.enumerated() where !routes.contains(where: { $0.id == index }) {
                        group.addTask {
                            await Self.plan(id: index, from: start, bearing: bearing, target: target, type: type, directions: directions)
                        }
                    }
                    for await plan in group {
                        guard !Task.isCancelled else { continue }
                        if plan.throttled {
                            // Stop asking: every request now only extends the wait.
                            throttled = true
                            group.cancelAll()
                        }
                        if let route = plan.route {
                            routes.append(route)
                            routes.sort { $0.id < $1.id }
                            if selectedID == nil { selectedID = route.id }
                        }
                    }
                }
                guard !Task.isCancelled else { return }
                // Throttled before finding anything: wait it out and try again.
                guard throttled, routes.isEmpty else { break }
                isThrottled = true
                try? await Task.sleep(for: throttleWait)
                guard !Task.isCancelled else { return }
            }
            isLoading = false
            isThrottled = throttled
            failed = routes.isEmpty
            // A throttled, partial result isn't cached, so coming back tries again.
            if !routes.isEmpty, !throttled { cache[target] = routes }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    /// The result of planning one loop.
    struct Plan: Sendable {
        var route: SuggestedRoute?
        /// Apple Maps stopped answering for now; `route` is the best before that.
        var throttled = false
    }

    /// One loop heading out towards `bearing`, resized until its road length
    /// is close to `target`. The closest attempt wins.
    nonisolated static func plan(
        id: Int,
        from start: Coordinate,
        bearing: Double,
        target: Double,
        type: ActivityType,
        directions: any DirectionsProvider
    ) async -> Plan {
        var radius = LoopPlanner.initialRadius(for: target)
        var best: SuggestedRoute?
        for _ in 0..<LoopPlanner.maxAttempts {
            guard !Task.isCancelled else { return Plan(route: nil) }
            let stops = LoopPlanner.waypoints(from: start, bearing: bearing, radius: radius)
            let legs: [DirectionsLeg]
            do {
                legs = try await Self.legs(between: stops, type: type, directions: directions)
            } catch DirectionsError.throttled {
                return Plan(route: best, throttled: true)
            } catch {
                // Waypoints may land somewhere unreachable; a smaller loop may work.
                radius *= 0.8
                continue
            }
            let route = SuggestedRoute(
                id: id,
                bearing: bearing,
                coordinates: legs.flatMap(\.coordinates),
                distance: legs.reduce(0) { $0 + $1.distance }
            )
            if best.map({ abs($0.distance - target) > abs(route.distance - target) }) ?? true {
                best = route
            }
            if LoopPlanner.isCloseEnough(route.distance, to: target) { break }
            radius = LoopPlanner.adjustedRadius(radius, target: target, actual: route.distance)
        }
        return Plan(route: best)
    }

    /// Directions for every leg, one at a time: with the three loops planned
    /// in parallel that's three requests in flight, which the Maps service
    /// handles, where a burst of a dozen makes it drop connections.
    nonisolated private static func legs(
        between stops: [Coordinate],
        type: ActivityType,
        directions: any DirectionsProvider
    ) async throws -> [DirectionsLeg] {
        var legs: [DirectionsLeg] = []
        for (from, to) in zip(stops, stops.dropFirst()) {
            try Task.checkCancellation()
            legs.append(try await directions.leg(from: from, to: to, for: type))
        }
        return legs
    }
}
