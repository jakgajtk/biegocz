import Foundation

/// Distance over a time span, for writing distance samples to Health.
struct DistanceChunk: Equatable, Sendable {
    var start: Date
    var end: Date
    var meters: Double
}

enum RouteSummaries {
    /// Total length of all segments; equals `CardioEngine.distance`.
    static func length(of segments: [[RoutePoint]]) -> Double {
        segments.reduce(0) { total, segment in
            total + zip(segment, segment.dropFirst()).reduce(0) { $0 + GeoMath.distance($1.0, $1.1) }
        }
    }

    /// Splits the route into chunks of at most `maxDuration` seconds, never
    /// spanning a pause. Chunks with no distance are left out.
    static func distanceChunks(of segments: [[RoutePoint]], maxDuration: TimeInterval = 60) -> [DistanceChunk] {
        var chunks: [DistanceChunk] = []
        for segment in segments {
            guard var chunkStart = segment.first else { continue }
            var meters = 0.0
            var previous = chunkStart
            for point in segment.dropFirst() {
                meters += GeoMath.distance(previous, point)
                previous = point
                if point.timestamp.timeIntervalSince(chunkStart.timestamp) >= maxDuration {
                    chunks.append(DistanceChunk(start: chunkStart.timestamp, end: point.timestamp, meters: meters))
                    chunkStart = point
                    meters = 0
                }
            }
            if meters > 0, previous.timestamp > chunkStart.timestamp {
                chunks.append(DistanceChunk(start: chunkStart.timestamp, end: previous.timestamp, meters: meters))
            }
        }
        return chunks
    }

    /// The gaps between segments, i.e. when the activity was paused.
    static func pauses(between segments: [[RoutePoint]]) -> [DateInterval] {
        let nonEmpty = segments.filter { !$0.isEmpty }
        return zip(nonEmpty, nonEmpty.dropFirst()).compactMap { before, after in
            guard let end = before.last?.timestamp, let start = after.first?.timestamp, start > end else { return nil }
            return DateInterval(start: end, end: start)
        }
    }
}
