import Foundation
import SwiftData

/// Imports runs and rides from GPX, TCX and FIT files (Strava account
/// export, MapMyRun downloads). Adds only what's missing: an activity of the
/// same type starting within `duplicateWindow` of an existing one is skipped,
/// so importing twice, or the same run from two services, changes nothing.
/// Imported activities are not written to Health.
enum HistoryImporter {
    struct Result: Equatable, Sendable {
        var added = 0
        /// Already in the app.
        var duplicates = 0
        /// Other sports, or no GPS track.
        var skipped = 0
        /// Unreadable files.
        var failed = 0
    }

    enum Outcome: Equatable, Sendable {
        case activity(ImportedActivity)
        case skipped
        case failed
    }

    static let duplicateWindow: TimeInterval = 120

    /// Reads one file off the main actor.
    @concurrent
    static func read(_ url: URL) async -> Outcome {
        guard let data = try? Data(contentsOf: url),
              let track = try? ActivityFile.read(data, fileName: url.lastPathComponent)
        else { return .failed }
        return TrackImport.activity(from: track).map(Outcome.activity) ?? .skipped
    }

    @MainActor
    static func importFiles(
        _ urls: [URL],
        into context: ModelContext,
        onProgress: (Int) -> Void = { _ in }
    ) async throws -> Result {
        var result = Result()
        var existing = try context.fetch(FetchDescriptor<Activity>())
            .filter { $0.type != .gym }
            .map { (type: $0.type, start: $0.startDate) }

        for (index, url) in urls.enumerated() {
            switch await read(url) {
            case .activity(let imported):
                if existing.contains(where: { $0.type == imported.type && abs($0.start.timeIntervalSince(imported.start)) <= duplicateWindow }) {
                    result.duplicates += 1
                } else {
                    insert(imported, into: context)
                    existing.append((imported.type, imported.start))
                    result.added += 1
                }
            case .skipped:
                result.skipped += 1
            case .failed:
                result.failed += 1
            }
            if index % 50 == 49 { try context.save() }
            onProgress(index + 1)
        }
        try context.save()
        return result
    }

    @MainActor
    static func insert(_ imported: ImportedActivity, into context: ModelContext) {
        let activity = Activity(type: imported.type, startDate: imported.start)
        activity.endDate = imported.end
        activity.isFinished = true
        activity.elapsedSeconds = imported.elapsedSeconds
        activity.movingSeconds = imported.movingSeconds
        activity.distanceMeters = imported.distanceMeters
        activity.elevationGainMeters = imported.elevationGainMeters
        activity.routeData = RouteCodec.encode(segments: imported.segments)
        context.insert(activity)
    }
}
