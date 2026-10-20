import Foundation

/// Unpacks `.gz` files (RFC 1952). The DEFLATE stream inside is inflated
/// with Foundation's `.zlib` algorithm, which is raw DEFLATE (RFC 1951).
enum Gzip {
    enum GzipError: Error {
        case notGzip
        case corrupt
    }

    static func isGzip(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == 0x1F && data[data.startIndex + 1] == 0x8B
    }

    static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        // Header: magic (2), method (1), flags (1), mtime (4), extra flags (1), OS (1).
        guard bytes.count >= 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else {
            throw GzipError.notGzip
        }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard offset + 2 <= bytes.count else { throw GzipError.corrupt }
            offset += 2 + Int(bytes[offset]) + Int(bytes[offset + 1]) << 8
        }
        if flags & 0x08 != 0 { offset = try skipZeroTerminated(bytes, from: offset) } // FNAME
        if flags & 0x10 != 0 { offset = try skipZeroTerminated(bytes, from: offset) } // FCOMMENT
        if flags & 0x02 != 0 { offset += 2 } // FHCRC
        // The last 8 bytes are the CRC-32 and the uncompressed size.
        guard offset < bytes.count - 8 else { throw GzipError.corrupt }

        let deflated = Data(bytes[offset..<(bytes.count - 8)])
        do {
            return try (deflated as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw GzipError.corrupt
        }
    }

    private static func skipZeroTerminated(_ bytes: [UInt8], from start: Int) throws -> Int {
        guard let end = bytes[start...].firstIndex(of: 0) else { throw GzipError.corrupt }
        return end + 1
    }
}
