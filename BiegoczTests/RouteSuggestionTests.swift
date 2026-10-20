import Foundation
import Testing
@testable import Biegocz

/// Straight lines between stops, made longer by a fixed factor, like roads.
private struct FakeDirections: DirectionsProvider {
    var detour = 1.4
    var failsBeyondMeters: Double = .infinity
    var budget: RequestBudget?

    func leg(from start: Coordinate, to end: Coordinate, for activity: ActivityType) async throws -> DirectionsLeg {
        if let budget, await !budget.take() { throw DirectionsError.throttled }
        let straight = GeoMath.distance(start, end)
        guard straight < failsBeyondMeters else { throw URLError(.cannotFindHost) }
        return DirectionsLeg(coordinates: [start, end], distance: straight * detour)
    }
}

/// Allows a number of requests, then throttles until refilled, like Apple Maps.
private actor RequestBudget {
    private(set) var remaining: Int
    private(set) var used = 0

    init(_ remaining: Int) {
        self.remaining = remaining
    }

    func take() -> Bool {
        guard remaining > 0 else { return false }
        remaining -= 1
        used += 1
        return true
    }

    func refill(_ count: Int) {
        remaining = count
    }
}

struct LoopPlannerTests {
    private let warsaw = Coordinate(latitude: 52.2297, longitude: 21.0122)

    @Test func destinationIsTheRequestedDistanceAway() {
        for bearing in stride(from: 0.0, to: 360, by: 45) {
            let point = GeoMath.destination(from: warsaw, bearing: bearing, meters: 1_000)
            #expect(abs(GeoMath.distance(warsaw, point) - 1_000) < 0.5)
        }
        let north = GeoMath.destination(from: warsaw, bearing: 0, meters: 1_000)
        #expect(north.latitude > warsaw.latitude)
        #expect(abs(north.longitude - warsaw.longitude) < 1e-9)
    }

    @Test func waypointsFormALoopInTheGivenDirection() {
        let radius = 800.0
        let stops = LoopPlanner.waypoints(from: warsaw, bearing: 90, radius: radius)
        #expect(stops.count == LoopPlanner.waypointCount + 2)
        #expect(stops.first == warsaw)
        #expect(stops.last == warsaw)
        // All stops lie on the circle around a centre east of the start.
        let center = GeoMath.destination(from: warsaw, bearing: 90, meters: radius)
        for stop in stops {
            #expect(abs(GeoMath.distance(center, stop) - radius) < 1)
        }
        #expect(stops.dropFirst().dropLast().allSatisfy { $0.longitude > warsaw.longitude - 1e-9 })
    }

    @Test func initialRadiusAimsAtTheTargetWithTypicalDetours() {
        let target = 10_000.0
        let radius = LoopPlanner.initialRadius(for: target)
        let straight = GeoMath.length(of: LoopPlanner.waypoints(from: warsaw, bearing: 0, radius: radius))
        #expect(abs(straight * LoopPlanner.detourFactor - target) < 50)
    }

    @Test func radiusAdjustmentIsProportionalButBounded() {
        #expect(LoopPlanner.adjustedRadius(1_000, target: 10_000, actual: 12_500) == 800)
        #expect(LoopPlanner.adjustedRadius(1_000, target: 10_000, actual: 1_000) == 2_000)
        #expect(LoopPlanner.adjustedRadius(1_000, target: 10_000, actual: 0) == 1_000)
        #expect(LoopPlanner.isCloseEnough(10_900, to: 10_000))
        #expect(!LoopPlanner.isCloseEnough(11_200, to: 10_000))
    }

    @Test func bearingsAreSpreadEvenly() {
        #expect(LoopPlanner.bearings(count: 3, offset: 0) == [0, 120, 240])
        #expect(LoopPlanner.bearings(count: 3, offset: 300) == [300, 60, 180])
    }

    @Test func compassNames() {
        #expect(Compass.heading(0) == "Heads north")
        #expect(Compass.heading(350) == "Heads north")
        #expect(Compass.heading(100) == "Heads east")
        #expect(Compass.heading(-90) == "Heads west")
        #expect(Compass.heading(225) == "Heads southwest")
    }
}

@MainActor
struct RouteSuggestionsModelTests {
    private let start = Coordinate(latitude: 52.2297, longitude: 21.0122)

    @Test func planResizesUntilCloseToTheTarget() async throws {
        // Roads twice as long as straight lines: the first guess is far off, the second is sized from it.
        let plan = await RouteSuggestionsModel.plan(
            id: 0, from: start, bearing: 45, target: 10_000, type: .run, directions: FakeDirections(detour: 2)
        )
        let route = try #require(plan.route)
        #expect(!plan.throttled)
        #expect(LoopPlanner.isCloseEnough(route.distance, to: 10_000))
        #expect(route.coordinates.first == start)
        #expect(route.coordinates.last == start)
        #expect(route.bearing == 45)
    }

    @Test func planUsesAtMostSixRequests() async {
        let budget = RequestBudget(100)
        _ = await RouteSuggestionsModel.plan(
            id: 0, from: start, bearing: 0, target: 10_000, type: .run, directions: FakeDirections(detour: 2.5, budget: budget)
        )
        #expect(await budget.used == LoopPlanner.maxAttempts * (LoopPlanner.waypointCount + 1))
    }

    @Test func planShrinksWhenWaypointsAreUnreachable() async throws {
        // Legs longer than 2.2 km fail; the first guess for 10 km has ~2.6 km legs.
        let plan = await RouteSuggestionsModel.plan(
            id: 0, from: start, bearing: 0, target: 10_000, type: .run,
            directions: FakeDirections(detour: 1.3, failsBeyondMeters: 2_200)
        )
        let found = try #require(plan.route)
        #expect(found.distance < 10_000)
    }

    @Test func planStopsWhenThrottled() async {
        let budget = RequestBudget(2)
        let plan = await RouteSuggestionsModel.plan(
            id: 0, from: start, bearing: 0, target: 10_000, type: .run, directions: FakeDirections(budget: budget)
        )
        #expect(plan.throttled)
        #expect(plan.route == nil)
        #expect(await budget.used == 2)
    }

    @Test func throttledWithNothingWaitsAndTriesAgain() async {
        let budget = RequestBudget(0)
        let model = RouteSuggestionsModel(
            type: .run, start: start, directions: FakeDirections(budget: budget), throttleWait: .milliseconds(50)
        )
        model.load()
        while !model.isThrottled { await Task.yield() }
        #expect(model.isLoading)
        await budget.refill(100)
        while model.isLoading { await Task.yield() }
        #expect(model.routes.count == 3)
        #expect(!model.isThrottled)
        #expect(!model.failed)
    }

    @Test func throttledHalfwayKeepsWhatItFoundWithoutCaching() async {
        // Enough for one loop (two attempts of three legs) and a bit more.
        let budget = RequestBudget(7)
        let model = RouteSuggestionsModel(type: .run, start: start, directions: FakeDirections(budget: budget))
        model.load()
        while model.isLoading { await Task.yield() }
        #expect(!model.routes.isEmpty)
        #expect(model.routes.count < 3)
        #expect(model.isThrottled)

        // Coming back to the distance plans again instead of showing the partial result.
        await budget.refill(100)
        model.setTarget(8_000)
        model.setTarget(5_000)
        while model.isLoading { await Task.yield() }
        #expect(model.routes.count == 3)
        #expect(!model.isThrottled)
    }

    @Test func revisitingADistanceUsesTheCache() async {
        let budget = RequestBudget(1_000)
        let model = RouteSuggestionsModel(type: .run, start: start, directions: FakeDirections(budget: budget))
        model.load()
        while model.isLoading { await Task.yield() }
        let used = await budget.used
        model.setTarget(8_000)
        while model.isLoading { await Task.yield() }
        model.setTarget(5_000)
        #expect(!model.isLoading)
        #expect(model.routes.count == 3)
        #expect(await budget.used > used)
        let afterEight = await budget.used
        model.setTarget(8_000)
        #expect(await budget.used == afterEight)
    }

    @Test func quickTapsOnlyPlanTheLastDistance() async {
        let budget = RequestBudget(1_000)
        let model = RouteSuggestionsModel(type: .run, start: start, directions: FakeDirections(budget: budget))
        for km in [8.0, 10, 15, 3] {
            model.setTarget(km * 1000)
        }
        while model.isLoading { await Task.yield() }
        #expect(model.targetDistance == 3_000)
        #expect(model.routes.count == 3)
        #expect(await budget.used <= 3 * LoopPlanner.maxAttempts * (LoopPlanner.waypointCount + 1))
    }

    @Test func loadOffersThreeRoutesAndSelectsOne() async throws {
        let model = RouteSuggestionsModel(type: .ride, start: start, directions: FakeDirections())
        #expect(model.targetDistance == 20_000)
        model.load()
        while model.isLoading { await Task.yield() }
        #expect(model.routes.map(\.id) == [0, 1, 2])
        // The first one to arrive is selected.
        #expect(model.selected != nil)
        #expect(!model.failed)
        #expect(Set(model.routes.map(\.bearing)).count == 3)
    }

    @Test func nothingFoundIsReported() async {
        let model = RouteSuggestionsModel(type: .run, start: start, directions: FakeDirections(failsBeyondMeters: 1))
        model.load()
        while model.isLoading { await Task.yield() }
        #expect(model.routes.isEmpty)
        #expect(model.failed)
    }
}
