import Foundation
import Testing
@testable import Biegocz

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func point(north meters: Double, at seconds: Double, accuracy: Double = 5) -> RoutePoint {
    RoutePoint(
        latitude: 52.2 + meters / 111_195,
        longitude: 21.0,
        altitude: 100,
        timestamp: t0.addingTimeInterval(seconds),
        horizontalAccuracy: accuracy
    )
}

struct GeoMathTests {
    @Test func oneDegreeOfLatitudeIsAbout111Km() {
        let a = RoutePoint(latitude: 52, longitude: 21, altitude: 0, timestamp: t0, horizontalAccuracy: 5)
        let b = RoutePoint(latitude: 53, longitude: 21, altitude: 0, timestamp: t0, horizontalAccuracy: 5)
        #expect(abs(GeoMath.distance(a, b) - 111_195) < 50)
    }

    @Test func helperPointsAreTheRequestedDistanceApart() {
        #expect(abs(GeoMath.distance(point(north: 0, at: 0), point(north: 100, at: 0)) - 100) < 0.1)
    }
}

struct GPSQualityTests {
    @Test func thresholds() {
        #expect(GPSQuality(horizontalAccuracy: nil) == .none)
        #expect(GPSQuality(horizontalAccuracy: -1) == .none)
        #expect(GPSQuality(horizontalAccuracy: 5) == .good)
        #expect(GPSQuality(horizontalAccuracy: 20) == .ok)
        #expect(GPSQuality(horizontalAccuracy: 65) == .poor)
    }
}

struct LocationFilterTests {
    @Test func firstValidPointIsAcceptedWithoutDistance() {
        var filter = LocationFilter(config: .run)
        #expect(filter.process(point(north: 0, at: 0), receivedAt: t0) == .accepted(distance: 0))
    }

    @Test func dropsInvalidInaccurateAndStaleFixes() {
        var filter = LocationFilter(config: .run)
        #expect(filter.process(point(north: 0, at: 0, accuracy: -1), receivedAt: t0) == .rejected(.invalid))
        #expect(filter.process(point(north: 0, at: 0, accuracy: 30), receivedAt: t0) == .rejected(.inaccurate))
        #expect(filter.process(point(north: 0, at: 0), receivedAt: t0.addingTimeInterval(60)) == .rejected(.stale))
        #expect(filter.lastAccepted == nil)
    }

    @Test func dropsImpossibleRunJumpButAllowsItForRide() {
        var run = LocationFilter(config: .run)
        _ = run.process(point(north: 0, at: 0), receivedAt: t0)
        // 15 m/s: too fast for a run, fine on a bike.
        #expect(run.process(point(north: 15, at: 1), receivedAt: t0.addingTimeInterval(1)) == .rejected(.impossibleSpeed))

        var ride = LocationFilter(config: .ride)
        _ = ride.process(point(north: 0, at: 0), receivedAt: t0)
        guard case .accepted(let distance) = ride.process(point(north: 15, at: 1), receivedAt: t0.addingTimeInterval(1)) else {
            Issue.record("Expected the ride fix to be accepted")
            return
        }
        #expect(abs(distance - 15) < 0.1)
    }

    @Test func jitterBelowMinimumMovementAddsNothing() {
        var filter = LocationFilter(config: .run)
        _ = filter.process(point(north: 0, at: 0), receivedAt: t0)
        for second in 1...30 {
            let wobble = second.isMultiple(of: 2) ? 2.0 : -2.0
            #expect(filter.process(point(north: wobble, at: Double(second)), receivedAt: t0.addingTimeInterval(Double(second))) == .stationary)
        }
    }

    @Test func slowMovementStillAddsUpAgainstLastAcceptedPoint() {
        var filter = LocationFilter(config: .run)
        var total = 0.0
        // 1 m/s walk: each fix is only 1 m from the previous one.
        for second in 0...20 {
            let time = t0.addingTimeInterval(Double(second))
            if case .accepted(let distance) = filter.process(point(north: Double(second), at: Double(second)), receivedAt: time) {
                total += distance
            }
        }
        #expect(abs(total - 20) < 0.1)
    }

    @Test func reanchorsAfterRepeatedJumps() {
        var filter = LocationFilter(config: .run)
        _ = filter.process(point(north: 0, at: 0), receivedAt: t0)
        // The first point was wrong; the real position is 500 m away.
        for second in 1..<5 {
            #expect(filter.process(point(north: 500, at: Double(second)), receivedAt: t0.addingTimeInterval(Double(second))) == .rejected(.impossibleSpeed))
        }
        #expect(filter.process(point(north: 500, at: 5), receivedAt: t0.addingTimeInterval(5)) == .accepted(distance: 0))
        #expect(filter.process(point(north: 510, at: 8), receivedAt: t0.addingTimeInterval(8)) != .rejected(.impossibleSpeed))
    }
}

struct SpeedSmootherTests {
    @Test func steadySpeed() throws {
        var smoother = SpeedSmoother(movingSpeed: 0.8)
        for second in 0...40 {
            smoother.add(time: t0.addingTimeInterval(Double(second)), totalDistance: Double(second) * 3)
        }
        let speed = try #require(smoother.currentSpeed(at: t0.addingTimeInterval(40)))
        #expect(abs(speed - 3) < 0.01)
        #expect(smoother.samples.count <= 27)
    }

    @Test func noReadingUntilFiveSeconds() {
        var smoother = SpeedSmoother(movingSpeed: 0.8)
        smoother.add(time: t0, totalDistance: 0)
        smoother.add(time: t0.addingTimeInterval(3), totalDistance: 9)
        #expect(smoother.currentSpeed(at: t0.addingTimeInterval(3)) == nil)
    }

    @Test func standingStillShowsNoPace() {
        var smoother = SpeedSmoother(movingSpeed: 0.8)
        for second in 0...20 { smoother.add(time: t0.addingTimeInterval(Double(second)), totalDistance: Double(second) * 3) }
        for second in 21...60 { smoother.add(time: t0.addingTimeInterval(Double(second)), totalDistance: 60) }
        #expect(smoother.currentSpeed(at: t0.addingTimeInterval(60)) == nil)
    }

    @Test func silenceDropsTheReading() {
        var smoother = SpeedSmoother(movingSpeed: 0.8)
        for second in 0...20 { smoother.add(time: t0.addingTimeInterval(Double(second)), totalDistance: Double(second) * 3) }
        #expect(smoother.currentSpeed(at: t0.addingTimeInterval(21)) != nil)
        #expect(smoother.currentSpeed(at: t0.addingTimeInterval(35)) == nil)
    }

    @Test func paceConversion() {
        #expect(Pace.secondsPerKilometer(metersPerSecond: 1000 / 300) == 300)
        #expect(Pace.secondsPerKilometer(metersPerSecond: nil) == nil)
        #expect(Pace.secondsPerKilometer(metersPerSecond: 0) == nil)
    }
}

struct SplitsTests {
    @Test func evenPaceGivesEqualSplits() {
        // 2.5 km at 4 m/s (4:10/km), one fix per second.
        let points = TestSupport.straightLine(seconds: 625, speed: 4, start: t0)
        let splits = Splits.perKilometer(segments: [points])
        #expect(splits.count == 3)
        #expect(splits.prefix(2).allSatisfy { abs($0.duration - 250) < 0.5 && $0.distance == 1000 })
        #expect(abs(splits[2].distance - 500) < 1)
        #expect(abs(splits[2].secondsPerKilometer - 250) < 1)
    }

    @Test func pausesAreNotCounted() {
        // 600 m, a 10 minute pause, then 600 m more, all at 4 m/s.
        let first = TestSupport.straightLine(seconds: 150, speed: 4, start: t0)
        let second = TestSupport.straightLine(seconds: 150, speed: 4, start: t0.addingTimeInterval(750))
            .map { var p = $0; p.latitude += 600 / 111_195; return p }
        let splits = Splits.perKilometer(segments: [first, second])
        #expect(abs(splits[0].duration - 250) < 0.5)
    }

    @Test func tinyRemainderIsDropped() {
        let points = TestSupport.straightLine(seconds: 255, speed: 4, start: t0) // 1020 m
        #expect(Splits.perKilometer(segments: [points]).count == 1)
    }
}

struct CardioEngineTests {
    @Test func sampleRunMeasuresAboutFiveKilometers() throws {
        let points = try TestSupport.sampleRoute("SampleRun")
        var engine = CardioEngine(activityType: .run, startDate: points[0].timestamp)
        var rejectedJumps = 0
        for point in points {
            if engine.ingest(point, receivedAt: point.timestamp) == .rejected(.impossibleSpeed) {
                rejectedJumps += 1
            }
        }
        // The loop is ~4.97 km; the 300 m spike must not count.
        #expect(engine.distance > 4_850 && engine.distance < 5_100, "distance \(engine.distance)")
        #expect(rejectedJumps >= 1)
        let end = try #require(points.last?.timestamp)
        let splits = Splits.perKilometer(segments: engine.segments)
        #expect(splits.count == 5)
        #expect(engine.movingTime(at: end) == engine.elapsedTime(at: end))
    }

    @Test func sampleRideMeasuresAboutTwentyKilometers() throws {
        let points = try TestSupport.sampleRoute("SampleRide")
        var engine = CardioEngine(activityType: .ride, startDate: points[0].timestamp)
        for point in points { engine.ingest(point, receivedAt: point.timestamp) }
        #expect(engine.distance > 20_200 && engine.distance < 21_200, "distance \(engine.distance)")
        let speed = try #require(engine.averageSpeed(at: points.last!.timestamp))
        #expect(abs(speed * 3.6 - 25) < 1.5)
    }

    @Test func manualPauseStopsMovingTimeAndStartsNewSegment() {
        var engine = CardioEngine(activityType: .run, startDate: t0)
        for p in TestSupport.straightLine(seconds: 100, speed: 3, start: t0) { engine.ingest(p, receivedAt: p.timestamp) }
        engine.pause(at: t0.addingTimeInterval(100))
        // Points while paused are ignored.
        #expect(engine.ingest(point(north: 5_000, at: 150), receivedAt: t0.addingTimeInterval(150)) == nil)
        engine.resume(at: t0.addingTimeInterval(400))
        let after = TestSupport.straightLine(seconds: 100, speed: 3, start: t0.addingTimeInterval(400))
            .map { var p = $0; p.latitude += 1_000 / 111_195; return p }
        for p in after { engine.ingest(p, receivedAt: p.timestamp) }

        let end = t0.addingTimeInterval(500)
        #expect(engine.elapsedTime(at: end) == 500)
        #expect(engine.movingTime(at: end) == 200)
        #expect(engine.segments.count == 2)
        // The 700 m gap between the segments isn't counted.
        #expect(abs(engine.distance - 600) < 15)
    }

    @Test func currentSpeedIsNilWhilePaused() {
        var engine = CardioEngine(activityType: .run, startDate: t0)
        for p in TestSupport.straightLine(seconds: 30, speed: 3, start: t0) { engine.ingest(p, receivedAt: p.timestamp) }
        #expect(engine.currentSpeed(at: t0.addingTimeInterval(30)) != nil)
        engine.pause(at: t0.addingTimeInterval(30))
        #expect(engine.currentSpeed(at: t0.addingTimeInterval(30)) == nil)
    }

    @Test func persistedStateRoundTripsAndRecoversPaused() throws {
        var engine = CardioEngine(activityType: .run, startDate: t0)
        for p in TestSupport.straightLine(seconds: 60, speed: 3, start: t0) { engine.ingest(p, receivedAt: p.timestamp) }
        engine.savedAt = t0.addingTimeInterval(60)
        let data = try JSONEncoder().encode(engine)
        let segments = engine.segments

        var restored = try JSONDecoder().decode(CardioEngine.self, from: data)
        restored.recover(segments: segments)
        #expect(restored.state == .paused)
        #expect(restored.distance == engine.distance)
        #expect(restored.segments == segments)
        // An hour later the moving time is still the 60 s recorded before the crash.
        #expect(restored.movingTime(at: t0.addingTimeInterval(3_600)) == 60)
    }
}
