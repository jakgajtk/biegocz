import Foundation

/// GPX, TCX and FIT files, plain or gzipped (`.gpx.gz`, `.fit.gz`), as found
/// in a Strava account export or downloaded from MapMyRun.
enum ActivityFile {
    enum Format: Equatable, Sendable {
        case gpx, tcx, fit
    }

    enum ReadError: Error {
        case unsupported
    }

    /// The format a file name points to, or `nil` if it isn't an activity file.
    static func format(ofFileNamed name: String) -> Format? {
        var name = name.lowercased()
        if name.hasSuffix(".gz") { name.removeLast(3) }
        switch (name as NSString).pathExtension {
        case "gpx": return .gpx
        case "tcx": return .tcx
        case "fit": return .fit
        default: return nil
        }
    }

    static func read(_ data: Data, fileName: String) throws -> ImportedTrack {
        guard let format = format(ofFileNamed: fileName) else { throw ReadError.unsupported }
        let data = Gzip.isGzip(data) ? try Gzip.decompress(data) : data
        switch format {
        case .gpx: return try GPXParser.parseTrack(data)
        case .tcx: return try TCXParser.parse(data)
        case .fit: return try FITParser.parse(data)
        }
    }

    /// Activity files at `urls`, looking inside folders (and their subfolders).
    static func files(in urls: [URL]) -> [URL] {
        var result: [URL] = []
        for url in urls {
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            guard isFolder else {
                if format(ofFileNamed: url.lastPathComponent) != nil { result.append(url) }
                continue
            }
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            while let child = enumerator?.nextObject() as? URL {
                if format(ofFileNamed: child.lastPathComponent) != nil { result.append(child) }
            }
        }
        return result.sorted { $0.path < $1.path }
    }
}
