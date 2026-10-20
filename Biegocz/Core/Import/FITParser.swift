import Foundation

/// Reads the parts of a Garmin FIT activity file needed for importing:
/// GPS records and the session totals. Follows the FIT protocol: a file
/// header, then definition and data messages; everything else is skipped.
enum FITParser {
    enum ParseError: Error {
        case invalidFile
    }

    /// Seconds between 1970-01-01 and the FIT epoch, 1989-12-31 00:00 UTC.
    static let epochOffset: TimeInterval = 631_065_600

    private struct FieldDefinition {
        var number: UInt8
        var size: Int
    }

    private struct MessageDefinition {
        var globalNumber: UInt16
        var bigEndian: Bool
        var fields: [FieldDefinition]
        var developerBytes: Int
    }

    private enum Message {
        static let session: UInt16 = 18
        static let record: UInt16 = 20
        static let sport: UInt16 = 12
    }

    static func parse(_ data: Data) throws -> ImportedTrack {
        let bytes = [UInt8](data)
        guard bytes.count >= 12, bytes[8...11] == [0x2E, 0x46, 0x49, 0x54] else { throw ParseError.invalidFile } // ".FIT"
        let headerSize = Int(bytes[0])
        let dataSize = Int(unsigned(bytes, at: 4, size: 4, bigEndian: false))
        let end = headerSize + dataSize
        guard headerSize >= 12, end <= bytes.count else { throw ParseError.invalidFile }

        var definitions: [UInt8: MessageDefinition] = [:]
        var lastTimestamp: UInt32 = 0
        var points: [RoutePoint] = []
        var track = ImportedTrack()
        var sportCode: UInt64?
        var offset = headerSize

        while offset < end {
            let header = bytes[offset]
            offset += 1
            var compressedTime: UInt32?
            let local: UInt8
            if header & 0x80 != 0 {
                local = (header >> 5) & 0x03
                let timeOffset = UInt32(header & 0x1F)
                // Wrapping: a crafted timestamp near UInt32.max must not trap.
                var time = (lastTimestamp & ~0x1F) &+ timeOffset
                if timeOffset < lastTimestamp & 0x1F { time &+= 0x20 }
                compressedTime = time
                lastTimestamp = time
            } else if header & 0x40 != 0 {
                // Definition message.
                guard offset + 5 <= end else { throw ParseError.invalidFile }
                let bigEndian = bytes[offset + 1] == 1
                let global = UInt16(unsigned(bytes, at: offset + 2, size: 2, bigEndian: bigEndian))
                let count = Int(bytes[offset + 4])
                offset += 5
                guard offset + count * 3 <= end else { throw ParseError.invalidFile }
                let fields = (0..<count).map { index in
                    FieldDefinition(number: bytes[offset + index * 3], size: Int(bytes[offset + index * 3 + 1]))
                }
                offset += count * 3
                var developerBytes = 0
                if header & 0x20 != 0 {
                    guard offset < end else { throw ParseError.invalidFile }
                    let developerCount = Int(bytes[offset])
                    offset += 1
                    guard offset + developerCount * 3 <= end else { throw ParseError.invalidFile }
                    developerBytes = (0..<developerCount).reduce(0) { $0 + Int(bytes[offset + $1 * 3 + 1]) }
                    offset += developerCount * 3
                }
                definitions[header & 0x0F] = MessageDefinition(
                    globalNumber: global, bigEndian: bigEndian, fields: fields, developerBytes: developerBytes
                )
                continue
            } else {
                local = header & 0x0F
            }

            // Data message.
            guard let definition = definitions[local] else { throw ParseError.invalidFile }
            var values: [UInt8: UInt64] = [:]
            for field in definition.fields {
                guard offset + field.size <= end else { throw ParseError.invalidFile }
                if [1, 2, 4].contains(field.size) {
                    let value = unsigned(bytes, at: offset, size: field.size, bigEndian: definition.bigEndian)
                    if !isInvalid(value, size: field.size) { values[field.number] = value }
                }
                offset += field.size
            }
            offset += definition.developerBytes
            guard offset <= end else { throw ParseError.invalidFile }

            if let timestamp = values[253] {
                lastTimestamp = UInt32(timestamp)
            } else if let compressedTime {
                values[253] = UInt64(compressedTime)
            }

            switch definition.globalNumber {
            case Message.record:
                guard let time = values[253], let lat = values[0], let lon = values[1] else { continue }
                let altitude = values[78].map(scaledAltitude) ?? values[2].map(scaledAltitude) ?? 0
                points.append(RoutePoint(
                    latitude: degrees(lat),
                    longitude: degrees(lon),
                    altitude: altitude,
                    timestamp: date(time),
                    horizontalAccuracy: 5
                ))
            case Message.session:
                if sportCode == nil { sportCode = values[5] }
                if let elapsed = values[7] { track.elapsedSeconds = (track.elapsedSeconds ?? 0) + Double(elapsed) / 1000 }
                if let timer = values[8] { track.movingSeconds = (track.movingSeconds ?? 0) + Double(timer) / 1000 }
                if let distance = values[9] { track.distanceMeters = (track.distanceMeters ?? 0) + Double(distance) / 100 }
                if let ascent = values[22] { track.elevationGainMeters = (track.elevationGainMeters ?? 0) + Double(ascent) }
            case Message.sport:
                if sportCode == nil { sportCode = values[0] }
            default:
                break
            }
        }

        track.segments = points.isEmpty ? [] : [points]
        track.sport = sportCode.flatMap { sport($0) }
        return track
    }

    /// FIT `sport` enum: 0 generic, 1 running, 2 cycling, everything else is another sport.
    static func sport(_ code: UInt64) -> ImportedTrack.Sport? {
        switch code {
        case 0: nil
        case 1: .run
        case 2: .ride
        default: .other
        }
    }

    static func date(_ fitTime: UInt64) -> Date {
        Date(timeIntervalSince1970: Double(fitTime) + epochOffset)
    }

    /// Semicircles (signed 32-bit) to degrees.
    static func degrees(_ semicircles: UInt64) -> Double {
        Double(Int32(bitPattern: UInt32(truncatingIfNeeded: semicircles))) * 180 / 2_147_483_648
    }

    /// `altitude` and `enhanced_altitude`: scale 5, offset 500 m.
    static func scaledAltitude(_ raw: UInt64) -> Double {
        Double(raw) / 5 - 500
    }

    /// The "invalid" value of the unsigned (all bits set) and signed
    /// (maximum) base types of this size.
    private static func isInvalid(_ value: UInt64, size: Int) -> Bool {
        let allSet: UInt64 = size == 8 ? .max : (1 << UInt64(size * 8)) - 1
        return value == allSet || value == allSet >> 1
    }

    private static func unsigned(_ bytes: [UInt8], at offset: Int, size: Int, bigEndian: Bool) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<size {
            let byte = UInt64(bytes[offset + (bigEndian ? index : size - 1 - index)])
            value = value << 8 | byte
        }
        return value
    }
}
