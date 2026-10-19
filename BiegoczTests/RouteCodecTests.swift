import Foundation
import Testing
@testable import Biegocz

struct RouteCodecTests {
    @Test func roundTrip() throws {
        let points = (0..<500).map { i in
            RoutePoint(
                latitude: 52.2297 + Double(i) * 0.0001,
                longitude: 21.0122 - Double(i) * 0.0001,
                altitude: 100 + Double(i % 7),
                timestamp: Date(timeIntervalSince1970: 1_760_000_000 + Double(i)),
                horizontalAccuracy: 4.5
            )
        }
        let data = RouteCodec.encode(points)
        #expect(data.count == 1 + points.count * 32)

        let decoded = try RouteCodec.decode(data)
        #expect(decoded.count == points.count)
        // Coordinates and time are lossless; altitude and accuracy are Float32.
        #expect(decoded.map(\.latitude) == points.map(\.latitude))
        #expect(decoded.map(\.longitude) == points.map(\.longitude))
        #expect(decoded.map(\.timestamp) == points.map(\.timestamp))
        #expect(decoded.map(\.altitude) == points.map(\.altitude))
        #expect(decoded.map(\.horizontalAccuracy) == points.map(\.horizontalAccuracy))
    }

    @Test func emptyRoute() throws {
        #expect(try RouteCodec.decode(RouteCodec.encode([])).isEmpty)
        #expect(try RouteCodec.decode(Data()).isEmpty)
    }

    @Test func rejectsUnknownVersionAndTruncatedData() {
        #expect(throws: RouteCodec.DecodingError.self) { try RouteCodec.decode(Data([99])) }
        var data = RouteCodec.encode([
            RoutePoint(latitude: 1, longitude: 2, altitude: 3, timestamp: .now, horizontalAccuracy: 4),
        ])
        data.removeLast()
        #expect(throws: RouteCodec.DecodingError.self) { try RouteCodec.decode(data) }
    }
}
