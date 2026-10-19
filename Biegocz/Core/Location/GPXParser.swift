import Foundation

/// Reads track points from a GPX file. Points without a `<time>` get
/// one-second spacing so they can still be replayed.
final class GPXParser: NSObject, XMLParserDelegate {
    enum ParseError: Error {
        case invalidFile
    }

    private var points: [RoutePoint] = []
    private var current: (latitude: Double, longitude: Double, altitude: Double, time: Date?)?
    private var text = ""
    private let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    private let fractionalDateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func parse(_ data: Data, startingAt start: Date = .now) throws -> [RoutePoint] {
        let delegate = GPXParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw ParseError.invalidFile }
        return delegate.points.enumerated().map { index, point in
            var point = point
            if point.timestamp == .distantPast {
                point.timestamp = start.addingTimeInterval(Double(index))
            }
            return point
        }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        text = ""
        guard elementName == "trkpt",
              let latitude = attributes["lat"].flatMap(Double.init),
              let longitude = attributes["lon"].flatMap(Double.init)
        else { return }
        current = (latitude, longitude, 0, nil)
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
            current?.time = (try? dateStyle.parse(value)) ?? (try? fractionalDateStyle.parse(value))
        case "trkpt":
            if let current {
                points.append(RoutePoint(
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
