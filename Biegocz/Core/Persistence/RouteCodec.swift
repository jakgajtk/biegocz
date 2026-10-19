import Foundation

/// Packs route points into a compact binary blob, stored once per activity.
///
/// Layout: 1 byte format version, then 32 bytes per point, little-endian:
/// latitude (Float64), longitude (Float64), timestamp since 1970 (Float64),
/// altitude (Float32), horizontal accuracy (Float32).
enum RouteCodec {
    static let formatVersion: UInt8 = 1
    private static let bytesPerPoint = 32

    enum DecodingError: Error {
        case unsupportedVersion(UInt8)
        case truncated
    }

    static func encode(_ points: [RoutePoint]) -> Data {
        var data = Data(capacity: 1 + points.count * bytesPerPoint)
        data.append(formatVersion)
        for point in points {
            append(point.latitude, to: &data)
            append(point.longitude, to: &data)
            append(point.timestamp.timeIntervalSince1970, to: &data)
            append(Float(point.altitude), to: &data)
            append(Float(point.horizontalAccuracy), to: &data)
        }
        return data
    }

    static func decode(_ data: Data) throws -> [RoutePoint] {
        guard let version = data.first else { return [] }
        guard version == formatVersion else { throw DecodingError.unsupportedVersion(version) }
        let body = data.dropFirst()
        guard body.count % bytesPerPoint == 0 else { throw DecodingError.truncated }

        var points: [RoutePoint] = []
        points.reserveCapacity(body.count / bytesPerPoint)
        var offset = body.startIndex
        while offset < body.endIndex {
            let latitude: Double = read(body, at: &offset)
            let longitude: Double = read(body, at: &offset)
            let time: Double = read(body, at: &offset)
            let altitude: Float = read(body, at: &offset)
            let accuracy: Float = read(body, at: &offset)
            points.append(RoutePoint(
                latitude: latitude,
                longitude: longitude,
                altitude: Double(altitude),
                timestamp: Date(timeIntervalSince1970: time),
                horizontalAccuracy: Double(accuracy)
            ))
        }
        return points
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
