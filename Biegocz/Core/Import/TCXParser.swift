import Foundation

/// Reads a Garmin Training Center (TCX) file, as exported by MapMyRun and
/// Strava. Each `<Track>` becomes a segment; lap totals give the distance
/// and the moving (timer) time.
final class TCXParser: NSObject, XMLParserDelegate {
    enum ParseError: Error {
        case invalidFile
    }

    private var sportName = ""
    private var segments: [[RoutePoint]] = []
    private var lapDistance = 0.0
    private var lapTime = 0.0
    private var hasLapTotals = false

    private var path: [String] = []
    private var point: (latitude: Double?, longitude: Double?, altitude: Double, time: Date?)?
    private var text = ""

    static func parse(_ data: Data) throws -> ImportedTrack {
        let delegate = TCXParser()
        let parser = XMLParser(data: XMLData.trimmingLeadingWhitespace(data))
        parser.delegate = delegate
        guard parser.parse() else { throw ParseError.invalidFile }
        return ImportedTrack(
            sport: ImportedTrack.Sport(name: delegate.sportName),
            segments: delegate.segments.filter { !$0.isEmpty },
            distanceMeters: delegate.hasLapTotals && delegate.lapDistance > 0 ? delegate.lapDistance : nil,
            movingSeconds: delegate.hasLapTotals && delegate.lapTime > 0 ? delegate.lapTime : nil
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        text = ""
        path.append(elementName)
        switch elementName {
        case "Activity" where sportName.isEmpty:
            sportName = attributes["Sport"] ?? ""
        case "Track":
            segments.append([])
        case "Trackpoint":
            point = (nil, nil, 0, nil)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        path.removeLast()
        let parent = path.last
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (elementName, parent) {
        case ("TotalTimeSeconds", "Lap"):
            lapTime += Double(value) ?? 0
            hasLapTotals = true
        case ("DistanceMeters", "Lap"):
            lapDistance += Double(value) ?? 0
            hasLapTotals = true
        case ("Time", "Trackpoint"):
            point?.time = XMLData.date(value)
        case ("AltitudeMeters", "Trackpoint"):
            point?.altitude = Double(value) ?? 0
        case ("LatitudeDegrees", "Position"):
            point?.latitude = Double(value)
        case ("LongitudeDegrees", "Position"):
            point?.longitude = Double(value)
        case ("Trackpoint", _):
            if let point, let latitude = point.latitude, let longitude = point.longitude, let time = point.time {
                if segments.isEmpty { segments.append([]) }
                segments[segments.count - 1].append(RoutePoint(
                    latitude: latitude,
                    longitude: longitude,
                    altitude: point.altitude,
                    timestamp: time,
                    horizontalAccuracy: 5
                ))
            }
            point = nil
        default:
            break
        }
        text = ""
    }
}
