import Foundation

/// Packs route points into a compact binary blob, stored once per activity.
/// A route is a list of segments; a new segment starts after every pause.
///
/// Version 2 layout: 1 byte format version, then 33 bytes per point,
/// little-endian: flags (UInt8, bit 0 = first point of a segment),
/// latitude (Float64), longitude (Float64), timestamp since 1970 (Float64),
/// altitude (Float32), horizontal accuracy (Float32).
/// Version 1 (no flags byte, one segment) is still decoded.
enum RouteCodec {
    static let formatVersion: UInt8 = 2
    private static let pointBytes = 32

    enum DecodingError: Error {
        case unsupportedVersion(UInt8)
        case truncated
    }

    static func encode(_ points: [RoutePoint]) -> Data {
        encode(segments: [points])
    }

    static func encode(segments: [[RoutePoint]]) -> Data {
        let count = segments.reduce(0) { $0 + $1.count }
        var data = Data(capacity: 1 + count * (pointBytes + 1))
        data.append(formatVersion)
        for segment in segments {
            for (index, point) in segment.enumerated() {
                data.append(index == 0 ? 1 : 0)
                append(point.latitude, to: &data)
                append(point.longitude, to: &data)
                append(point.timestamp.timeIntervalSince1970, to: &data)
                append(Float(point.altitude), to: &data)
                append(Float(point.horizontalAccuracy), to: &data)
            }
        }
        return data
    }

    static func decode(_ data: Data) throws -> [RoutePoint] {
        try decodeSegments(data).flatMap { $0 }
    }

    static func decodeSegments(_ data: Data) throws -> [[RoutePoint]] {
        guard let version = data.first else { return [] }
        let hasFlags: Bool
        switch version {
        case 1: hasFlags = false
        case 2: hasFlags = true
        default: throw DecodingError.unsupportedVersion(version)
        }
        let stride = pointBytes + (hasFlags ? 1 : 0)
        let body = data.dropFirst()
        guard body.count % stride == 0 else { throw DecodingError.truncated }

        var segments: [[RoutePoint]] = []
        var offset = body.startIndex
        while offset < body.endIndex {
            var startsSegment = segments.isEmpty
            if hasFlags {
                startsSegment = startsSegment || body[offset] & 1 == 1
                offset += 1
            }
            let latitude: Double = read(body, at: &offset)
            let longitude: Double = read(body, at: &offset)
            let time: Double = read(body, at: &offset)
            let altitude: Float = read(body, at: &offset)
            let accuracy: Float = read(body, at: &offset)
            let point = RoutePoint(
                latitude: latitude,
                longitude: longitude,
                altitude: Double(altitude),
                timestamp: Date(timeIntervalSince1970: time),
                horizontalAccuracy: Double(accuracy)
            )
            if startsSegment {
                segments.append([point])
            } else {
                segments[segments.count - 1].append(point)
            }
        }
        return segments
    }

    private static func append(_ value: Double, to data: inout Data) {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
    }

    private static func append(_ value: Float, to data: inout Data) {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
    }

    private static func read(_ data: Data, at offset: inout Data.Index) -> Double {
        var bits: UInt64 = 0
        for i in 0..<8 { bits |= UInt64(data[offset + i]) << (8 * UInt64(i)) }
        offset += 8
        return Double(bitPattern: bits)
    }

    private static func read(_ data: Data, at offset: inout Data.Index) -> Float {
        var bits: UInt32 = 0
        for i in 0..<4 { bits |= UInt32(data[offset + i]) << (8 * UInt32(i)) }
        offset += 4
        return Float(bitPattern: bits)
    }
}
