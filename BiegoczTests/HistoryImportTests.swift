import Foundation
import SwiftData
import Testing
@testable import Biegocz

/// FIT fixtures come from the python-fitparse test suite (MIT licence):
/// https://github.com/dtcooper/python-fitparse/tree/master/tests/files
private final class FixtureBundle {}

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle(for: FixtureBundle.self).url(forResource: name, withExtension: nil))
    return try Data(contentsOf: url)
}

private let start = Date(timeIntervalSince1970: 1_700_000_000)

struct ActivityFileTests {
    @Test func gzipWithFileNameHeader() throws {
        // `gzip -9 -N` of a UTF-8 text file, so the header carries the file name.
        let gz = try #require(Data(base64Encoded: "H4sICAoW12oCA2hlbGxvLnR4dABzykxNz0+uUkivyixQKEktLrFSqEo8uufw5qNNR9oV0o/MPDo750irQlbi0V1HW7gAm820ky4AAAA="))
        #expect(Gzip.isGzip(gz))
        #expect(try String(decoding: Gzip.decompress(gz), as: UTF8.self) == "Biegocz gzip test: zażółć gęślą jaźń\n")
        #expect(throws: Gzip.GzipError.self) { try Gzip.decompress(Data("plain".utf8)) }
    }

    @Test func formatsFromFileNames() {
        #expect(ActivityFile.format(ofFileNamed: "123.gpx") == .gpx)
        #expect(ActivityFile.format(ofFileNamed: "123.GPX.gz") == .gpx)
        #expect(ActivityFile.format(ofFileNamed: "123.tcx") == .tcx)
        #expect(ActivityFile.format(ofFileNamed: "123.fit.gz") == .fit)
        #expect(ActivityFile.format(ofFileNamed: "activities.csv") == nil)
        #expect(ActivityFile.format(ofFileNamed: "photo.jpg") == nil)
    }

    @Test func sportNames() {
        #expect(ImportedTrack.Sport(name: "running") == .run)
        #expect(ImportedTrack.Sport(name: "TrailRun") == .run)
        #expect(ImportedTrack.Sport(name: "Biking") == .ride)
        #expect(ImportedTrack.Sport(name: "cycling") == .ride)
        #expect(ImportedTrack.Sport(name: "Ride") == .ride)
        #expect(ImportedTrack.Sport(name: "VirtualRide") == .other)
        #expect(ImportedTrack.Sport(name: "Walk") == .other)
        #expect(ImportedTrack.Sport(name: "Other") == .other)
        #expect(ImportedTrack.Sport(name: "9") == nil)
        #expect(ImportedTrack.Sport(name: "") == nil)
    }

    @Test func gpxKeepsSegmentsAndType() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="StravaGPX" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata><time>2026-10-19T08:00:00Z</time></metadata>
          <trk><name>Morning Run</name><type>running</type>
            <trkseg>
              <trkpt lat="52.2297" lon="21.0122"><ele>101.5</ele><time>2026-10-19T08:00:00Z</time></trkpt>
              <trkpt lat="52.2300" lon="21.0130"><ele>102.0</ele><time>2026-10-19T08:00:05Z</time></trkpt>
            </trkseg>
            <trkseg>
              <trkpt lat="52.2310" lon="21.0140"><time>2026-10-19T08:05:00+02:00</time></trkpt>
              <trkpt lat="52.2320" lon="21.0150"/>
            </trkseg>
          </trk>
        </gpx>
        """
        let track = try GPXParser.parseTrack(Data(gpx.utf8))
        #expect(track.sport == .run)
        #expect(track.segments.map(\.count) == [2, 1])
        #expect(track.segments[0][0].altitude == 101.5)
        #expect(track.segments[1][0].timestamp == (try Date("2026-10-19T06:05:00Z", strategy: .iso8601)))
    }

    @Test func tcxWithLeadingWhitespace() throws {
        let tcx = """
                  <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
          <Activities>
            <Activity Sport="Biking">
              <Id>2019-05-01T06:00:00Z</Id>
              <Lap StartTime="2019-05-01T06:00:00Z">
                <TotalTimeSeconds>600</TotalTimeSeconds>
                <DistanceMeters>5000</DistanceMeters>
                <Track>
                  <Trackpoint>
                    <Time>2019-05-01T06:00:00Z</Time>
                    <Position><LatitudeDegrees>52.1</LatitudeDegrees><LongitudeDegrees>21.1</LongitudeDegrees></Position>
                    <AltitudeMeters>90</AltitudeMeters>
                    <DistanceMeters>0</DistanceMeters>
                  </Trackpoint>
                  <Trackpoint><Time>2019-05-01T06:00:01Z</Time><DistanceMeters>3</DistanceMeters></Trackpoint>
                  <Trackpoint>
                    <Time>2019-05-01T06:00:02Z</Time>
                    <Position><LatitudeDegrees>52.1001</LatitudeDegrees><LongitudeDegrees>21.1</LongitudeDegrees></Position>
                  </Trackpoint>
                </Track>
              </Lap>
              <Lap StartTime="2019-05-01T06:10:00Z">
                <TotalTimeSeconds>300</TotalTimeSeconds>
                <DistanceMeters>2500</DistanceMeters>
                <Track/>
              </Lap>
            </Activity>
          </Activities>
        </TrainingCenterDatabase>
        """
        let track = try ActivityFile.read(Data(tcx.utf8), fileName: "42.tcx")
        #expect(track.sport == .ride)
        #expect(track.distanceMeters == 7500)
        #expect(track.movingSeconds == 900)
        // The point without a position is skipped, and so is the empty track.
        #expect(track.segments.map(\.count) == [2])
        #expect(track.segments[0][0].altitude == 90)
    }

    @Test func fitRun() throws {
        let track = try ActivityFile.read(fixture("fenix5-run.fit"), fileName: "run.fit")
        #expect(track.sport == .run)
        let points = track.segments.flatMap { $0 }
        #expect(points.count == 21)
        // First record per fitparse's reference CSV: 07:34:09 PDT, semicircles 456099128 / -1463077077, 2.2 m.
        let first = try #require(points.first)
        #expect(first.timestamp == (try Date("2017-06-11T14:34:09Z", strategy: .iso8601)))
        #expect(abs(first.latitude - 456_099_128 * 180 / 2_147_483_648) < 1e-9)
        #expect(abs(first.longitude - -1_463_077_077 * 180 / 2_147_483_648) < 1e-9)
        #expect(abs(first.altitude - 2.2) < 0.01)
        #expect(track.distanceMeters == 157.56)
        #expect(abs((track.movingSeconds ?? 0) - 56.887) < 0.001)
    }

    @Test func fitRide() throws {
        let track = try FITParser.parse(fixture("edge820-bike.fit"))
        #expect(track.sport == .ride)
        #expect(track.segments.flatMap { $0 }.count == 15)
        #expect(track.distanceMeters == 457.12)
    }

    @Test func fitWithoutGPSIsSkipped() throws {
        // A treadmill-style file with compressed timestamps and no positions.
        let track = try FITParser.parse(fixture("compressed.fit"))
        #expect(track.sport == .run)
        #expect(track.segments.isEmpty)
        #expect(TrackImport.activity(from: track) == nil)
    }

    @Test func notAFITFile() {
        #expect(throws: FITParser.ParseError.self) { try FITParser.parse(Data(repeating: 0, count: 64)) }
    }
}

struct TrackImportTests {
    @Test func splitsAtRecordingGapsAndUsesFileTotals() throws {
        let first = TestSupport.straightLine(seconds: 120, speed: 3, start: start)
        let second = TestSupport.straightLine(seconds: 120, speed: 3, start: start.addingTimeInterval(300))
            .map { point in
                var point = point
                point.latitude += 0.01
                return point
            }
        let track = ImportedTrack(sport: .run, segments: [first + second], distanceMeters: 750)
        let activity = try #require(TrackImport.activity(from: track))
        #expect(activity.type == .run)
        #expect(activity.segments.count == 2)
        #expect(activity.start == start)
        #expect(activity.elapsedSeconds == 420)
        #expect(activity.movingSeconds == 240)
        #expect(activity.distanceMeters == 750)
    }

    @Test func computesDistanceWhenTheFileHasNone() throws {
        let points = TestSupport.straightLine(seconds: 300, speed: 3, start: start)
        let activity = try #require(TrackImport.activity(from: ImportedTrack(sport: .run, segments: [points])))
        #expect(abs(activity.distanceMeters - 900) < 10)
        #expect(activity.movingSeconds == 300)
        // Flat route at 100 m: there is altitude, but no climb.
        #expect(activity.elevationGainMeters == 0)
    }

    @Test func infersTypeFromSpeedWhenTheFileDoesNotSay() throws {
        let slow = TestSupport.straightLine(seconds: 300, speed: 3, start: start)
        let fast = TestSupport.straightLine(seconds: 300, speed: 7, start: start)
        #expect(TrackImport.activity(from: ImportedTrack(segments: [slow]))?.type == .run)
        #expect(TrackImport.activity(from: ImportedTrack(segments: [fast]))?.type == .ride)
    }

    @Test func otherSportsAreSkipped() {
        let points = TestSupport.straightLine(seconds: 300, speed: 1.4, start: start)
        #expect(TrackImport.activity(from: ImportedTrack(sport: .other, segments: [points])) == nil)
    }

    @Test func noAltitudeMeansNoElevation() throws {
        let points = TestSupport.straightLine(seconds: 60, speed: 3, start: start).map { point in
            var point = point
            point.altitude = 0
            return point
        }
        let activity = try #require(TrackImport.activity(from: ImportedTrack(sport: .run, segments: [points])))
        #expect(activity.elevationGainMeters == nil)
    }
}

@MainActor
struct HistoryImporterTests {
    private func gpx(type: String, start: Date, seconds: Int = 300, speed: Double = 3) -> String {
        let points = TestSupport.straightLine(seconds: seconds, speed: speed, start: start)
            .map { point in
                "<trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\"><ele>100</ele><time>\(point.timestamp.ISO8601Format())</time></trkpt>"
            }
            .joined()
        return "<gpx><trk><type>\(type)</type><trkseg>\(points)</trkseg></trk></gpx>"
    }

    private func write(_ files: [String: String], to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, contents) in files {
            try Data(contents.utf8).write(to: folder.appending(path: name))
        }
    }

    @Test func importsRunsAndRidesOnceAndSkipsTheRest() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let activities = folder.appending(path: "activities")
        try write([
            "1.gpx": gpx(type: "running", start: start),
            "2.gpx": gpx(type: "cycling", start: start.addingTimeInterval(86_400), speed: 7),
            "3.gpx": gpx(type: "walking", start: start.addingTimeInterval(2 * 86_400), speed: 1.4),
            "4.gpx": "not xml",
            // The same run again, recorded by another app a minute later.
            "5.gpx": gpx(type: "running", start: start.addingTimeInterval(60)),
        ], to: activities)
        try write(["activities.csv": "Activity ID,Activity Date\n"], to: folder)
        defer { try? FileManager.default.removeItem(at: folder) }

        let files = ActivityFile.files(in: [folder])
        #expect(files.map(\.lastPathComponent) == ["1.gpx", "2.gpx", "3.gpx", "4.gpx", "5.gpx"])

        var progress: [Int] = []
        let result = try await HistoryImporter.importFiles(files, into: context) { progress.append($0) }
        #expect(result == HistoryImporter.Result(added: 2, duplicates: 1, skipped: 1, failed: 1))
        #expect(progress == [1, 2, 3, 4, 5])

        let saved = try context.fetch(FetchDescriptor<Activity>(sortBy: [SortDescriptor(\.startDate)]))
        #expect(saved.map(\.type) == [.run, .ride])
        let run = try #require(saved.first)
        #expect(run.isFinished)
        #expect(run.healthKitWorkoutID == nil)
        #expect(abs(run.distanceMeters - 900) < 10)
        #expect(run.routeSegments.flatMap { $0 }.count > 100)

        // Importing the same folder again adds nothing.
        let again = try await HistoryImporter.importFiles(files, into: context)
        #expect(again.added == 0)
        #expect(again.duplicates == 3)
    }
}
