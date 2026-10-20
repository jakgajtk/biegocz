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
    var selectedID: Int?

    private let directions: any DirectionsProvider
    private var bearingOffset: Double
    private var task: Task<Void, Never>?

    init(type: ActivityType, start: Coordinate, directions: any DirectionsProvider, bearingOffset: Double = 0) {
        self.type = type
        self.start = start
        self.directions = directions
        self.bearingOffset = bearingOffset
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
        load()
    }

    /// New directions for the same distance.
    func shuffle() {
        bearingOffset = (bearingOffset + 360 / Double(Self.count) / 2).truncatingRemainder(dividingBy: 360)
        load()
    }

    func load() {
        task?.cancel()
        routes = []
        selectedID = nil
        failed = false
        isLoading = true
        let bearings = LoopPlanner.bearings(count: Self.count, offset: bearingOffset)
        let (start, target, type, directions) = (start, targetDistance, type, directions)
        task = Task {
            await withTaskGroup(of: SuggestedRoute?.self) { group in
                for (index, bearing) in bearings.enumerated() {
                    group.addTask {
                        await Self.plan(id: index, from: start, bearing: bearing, target: target, type: type, directions: directions)
                    }
                }
                for await route in group {
                    guard !Task.isCancelled, let route else { continue }
                    routes.append(route)
                    routes.sort { $0.id < $1.id }
                    if selectedID == nil { selectedID = route.id }
                }
            }
            guard !Task.isCancelled else { return }
            isLoading = false
            failed = routes.isEmpty
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    /// One loop heading out towards `bearing`, resized until its road length
    /// is close to `target`. The closest attempt wins; `nil` if no attempt
    /// found a route.
    nonisolated static func plan(
        id: Int,
        from start: Coordinate,
        bearing: Double,
        target: Double,
        type: ActivityType,
        directions: any DirectionsProvider
    ) async -> SuggestedRoute? {
        var radius = LoopPlanner.initialRadius(for: target)
        var best: SuggestedRoute?
        for _ in 0..<LoopPlanner.maxAttempts {
            guard !Task.isCancelled else { return nil }
            let stops = LoopPlanner.waypoints(from: start, bearing: bearing, radius: radius)
            guard let legs = try? await legs(between: stops, type: type, directions: directions) else {
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
        return best
    }

    /// Directions for every leg, fetched in parallel, in order.
    nonisolated private static func legs(
        between stops: [Coordinate],
        type: ActivityType,
        directions: any DirectionsProvider
    ) async throws -> [DirectionsLeg] {
        try await withThrowingTaskGroup(of: (Int, DirectionsLeg).self) { group in
            for (index, pair) in zip(stops, stops.dropFirst()).enumerated() {
                group.addTask { (index, try await directions.leg(from: pair.0, to: pair.1, for: type)) }
            }
            var legs: [(Int, DirectionsLeg)] = []
            for try await leg in group { legs.append(leg) }
            return legs.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}
