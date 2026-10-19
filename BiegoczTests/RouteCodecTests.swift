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
        #expect(data.count == 1 + points.count * 33)

        let decoded = try RouteCodec.decode(data)
        #expect(decoded.count == points.count)
        // Coordinates and time are lossless; altitude and accuracy are Float32.
        #expect(decoded.map(\.latitude) == points.map(\.latitude))
        #expect(decoded.map(\.longitude) == points.map(\.longitude))
        #expect(decoded.map(\.timestamp) == points.map(\.timestamp))
        #expect(decoded.map(\.altitude) == points.map(\.altitude))
        #expect(decoded.map(\.horizontalAccuracy) == points.map(\.horizontalAccuracy))
    }

    @Test func segmentsRoundTrip() throws {
        func point(_ i: Int) -> RoutePoint {
            RoutePoint(latitude: Double(i), longitude: 0, altitude: 0, timestamp: Date(timeIntervalSince1970: Double(i)), horizontalAccuracy: 5)
        }
        let segments = [[point(0), point(1), point(2)], [point(3)], [point(4), point(5)]]
        #expect(try RouteCodec.decodeSegments(RouteCodec.encode(segments: segments)) == segments)
    }

    @Test func decodesVersionOneAsSingleSegment() throws {
        // Version 1: no flags byte.
        var data = Data([1])
        for value in [52.0, 21.0, 1_000.0] {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        for value: Float in [100, 5] {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        let segments = try RouteCodec.decodeSegments(data)
        #expect(segments.count == 1)
        #expect(segments[0].first?.latitude == 52)
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
