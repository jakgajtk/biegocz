import Foundation

/// Reads track points from a GPX file, keeping `<trkseg>` boundaries and the
/// track's `<type>`.
final class GPXParser: NSObject, XMLParserDelegate {
    enum ParseError: Error {
        case invalidFile
    }

    private var segments: [[RoutePoint]] = []
    private var typeName = ""
    private var current: (latitude: Double, longitude: Double, altitude: Double, time: Date?)?
    private var text = ""

    /// All points in one list, for replay. Points without a `<time>` get
    /// one-second spacing.
    static func parse(_ data: Data, startingAt start: Date = .now) throws -> [RoutePoint] {
        let delegate = try run(data)
        return delegate.segments.flatMap { $0 }.enumerated().map { index, point in
            var point = point
            if point.timestamp == .distantPast {
                point.timestamp = start.addingTimeInterval(Double(index))
            }
            return point
        }
    }

    /// The recorded track, for importing. Points without a `<time>` are left out.
    static func parseTrack(_ data: Data) throws -> ImportedTrack {
        let delegate = try run(data)
        return ImportedTrack(
            sport: ImportedTrack.Sport(name: delegate.typeName),
            segments: delegate.segments
                .map { $0.filter { $0.timestamp != .distantPast } }
                .filter { !$0.isEmpty }
        )
    }

    private static func run(_ data: Data) throws -> GPXParser {
        let delegate = GPXParser()
        let parser = XMLParser(data: XMLData.trimmingLeadingWhitespace(data))
        parser.delegate = delegate
        guard parser.parse() else { throw ParseError.invalidFile }
        return delegate
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        text = ""
        switch elementName {
        case "trkseg":
            segments.append([])
        case "trkpt":
            guard let latitude = attributes["lat"].flatMap(Double.init),
                  let longitude = attributes["lon"].flatMap(Double.init)
            else { return }
            current = (latitude, longitude, 0, nil)
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
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "ele":
            current?.altitude = Double(value) ?? 0
        case "time":
            current?.time = XMLData.date(value)
        case "type" where current == nil:
            typeName = value
        case "trkpt":
            if let current {
                if segments.isEmpty { segments.append([]) }
                segments[segments.count - 1].append(RoutePoint(
                    latitude: current.latitude,
                    longitude: current.longitude,
                    altitude: current.altitude,
                    timestamp: current.time ?? .distantPast,
                    horizontalAccuracy: 5
                ))
            }
            current = nil
        default:
            break
        }
    }
}

/// Helpers shared by the XML-based readers.
enum XMLData {
    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    private static let fractionalDateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func date(_ text: String) -> Date? {
        (try? dateStyle.parse(text)) ?? (try? fractionalDateStyle.parse(text))
    }

    /// Some exporters (Strava's TCX among them) put whitespace before the XML
    /// declaration, which `XMLParser` rejects.
    static func trimmingLeadingWhitespace(_ data: Data) -> Data {
        guard let first = data.firstIndex(where: { ![0x20, 0x09, 0x0A, 0x0D].contains($0) }) else { return data }
        return first == data.startIndex ? data : data[first...]
    }
}
