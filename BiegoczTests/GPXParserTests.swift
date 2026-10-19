import Foundation
import Testing
@testable import Biegocz

struct GPXParserTests {
    @Test func parsesTrackPoints() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><trkseg>
            <trkpt lat="52.2297" lon="21.0122"><ele>101.5</ele><time>2026-10-19T08:00:00Z</time></trkpt>
            <trkpt lat="52.2300" lon="21.0130"><ele>102.0</ele><time>2026-10-19T08:00:05Z</time></trkpt>
          </trkseg></trk>
        </gpx>
        """
        let points = try GPXParser.parse(Data(gpx.utf8))
        #expect(points.count == 2)
        #expect(points[0].latitude == 52.2297)
        #expect(points[1].longitude == 21.0130)
        #expect(points[0].altitude == 101.5)
        #expect(points[1].timestamp.timeIntervalSince(points[0].timestamp) == 5)
    }

    @Test func pointsWithoutTimeGetOneSecondSpacing() throws {
        let gpx = """
        <gpx><trk><trkseg>
          <trkpt lat="1" lon="1"/><trkpt lat="1.001" lon="1"/>
        </trkseg></trk></gpx>
        """
        let start = Date(timeIntervalSince1970: 1_000)
        let points = try GPXParser.parse(Data(gpx.utf8), startingAt: start)
        #expect(points.map(\.timestamp) == [start, start.addingTimeInterval(1)])
    }
}
