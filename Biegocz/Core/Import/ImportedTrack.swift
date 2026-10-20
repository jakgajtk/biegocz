import Foundation

/// A recorded activity read from a GPX, TCX or FIT file, before it becomes
/// an app activity. Totals are the ones the file states, if any.
struct ImportedTrack: Equatable, Sendable {
    enum Sport: Equatable, Sendable {
        case run, ride, other

        /// Maps sport names used by GPX `<type>`, TCX and Strava, e.g. "running",
        /// "Biking", "TrailRun", "VirtualRide". `nil` for empty or numeric names.
        init?(name: String) {
            let name = name.lowercased()
            guard !name.isEmpty, Double(name) == nil else { return nil }
            if name.contains("virtual") {
                self = .other
            } else if name.contains("run") {
                self = .run
            } else if name.contains("cycl") || name.contains("bik") || name.contains("ride") {
                self = .ride
            } else {
                self = .other
            }
        }
    }

    /// `nil` when the file doesn't say.
    var sport: Sport?
    /// Track segments as stored in the file. Points without a time are left out.
    var segments: [[RoutePoint]] = []
    var distanceMeters: Double?
    var movingSeconds: Double?
    var elapsedSeconds: Double?
    var elevationGainMeters: Double?
}

/// A finished run or ride built from an `ImportedTrack`.
struct ImportedActivity: Equatable, Sendable {
    var type: ActivityType
    var start: Date
    var end: Date
    var elapsedSeconds: Double
    var movingSeconds: Double
    var distanceMeters: Double
    var elevationGainMeters: Double?
    var segments: [[RoutePoint]]
}

enum TrackImport {
    /// A gap in the recording longer than this (seconds) counts as a pause.
    static let pauseGap: TimeInterval = 60
    /// Without a sport in the file, faster than this on average (m/s) is a ride.
    static let rideSpeed = 4.5

    /// Turns a track into a run or ride, cleaned with the same GPS filter as
    /// live tracking. `nil` for other sports and tracks without GPS.
    static func activity(from track: ImportedTrack) -> ImportedActivity? {
        let raw = track.segments.flatMap(splitAtPauses).filter { $0.count >= 2 }
        guard let start = raw.first?.first?.timestamp, let end = raw.last?.last?.timestamp, end > start else {
            return nil
        }
        let recorded = raw.reduce(0) { $0 + $1.last!.timestamp.timeIntervalSince($1.first!.timestamp) }

        let type: ActivityType
        switch track.sport {
        case .run: type = .run
        case .ride: type = .ride
        case .other: return nil
        case nil:
            let speed = recorded > 0 ? RouteSummaries.length(of: raw) / recorded : 0
            type = speed >= rideSpeed ? .ride : .run
        }

        var filter = LocationFilter(config: .forActivity(type))
        var gain = ElevationGain.gps
        var segments: [[RoutePoint]] = []
        for segment in raw {
            filter.reset()
            gain.reset()
            var kept: [RoutePoint] = []
            for point in segment {
                guard case .accepted = filter.process(point, receivedAt: point.timestamp) else { continue }
                kept.append(point)
                gain.add(altitude: point.altitude)
            }
            if kept.count >= 2 { segments.append(kept) }
        }
        guard !segments.isEmpty else { return nil }

        let hasAltitude = raw.contains { $0.contains { $0.altitude != 0 } }
        let elapsed = plausible(track.elapsedSeconds) ?? end.timeIntervalSince(start)
        return ImportedActivity(
            type: type,
            start: start,
            end: max(end, start.addingTimeInterval(elapsed)),
            elapsedSeconds: elapsed,
            movingSeconds: min(plausible(track.movingSeconds) ?? recorded, elapsed),
            distanceMeters: plausible(track.distanceMeters) ?? RouteSummaries.length(of: segments),
            elevationGainMeters: plausible(track.elevationGainMeters) ?? (hasAltitude ? gain.total : nil),
            segments: segments
        )
    }

    /// Largest total taken from a file (seconds or meters, about 31 years or
    /// 1 million km). Anything bigger, negative or not finite is ignored.
    static let maxTotal = 1e9

    /// A file total if it's usable, otherwise `nil` so the track is used instead.
    static func plausible(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0, value <= maxTotal else { return nil }
        return value
    }

    /// Splits a segment wherever the recording stopped for longer than `pauseGap`.
    static func splitAtPauses(_ segment: [RoutePoint]) -> [[RoutePoint]] {
        var result: [[RoutePoint]] = []
        var current: [RoutePoint] = []
        for point in segment {
            if let last = current.last {
                let gap = point.timestamp.timeIntervalSince(last.timestamp)
                guard gap > 0 else { continue }
                if gap > pauseGap {
                    result.append(current)
                    current = []
                }
            }
            current.append(point)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
