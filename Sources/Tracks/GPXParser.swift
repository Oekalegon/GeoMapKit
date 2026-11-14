import Foundation
import GeoCore

/// Reads a GPX document with `XMLParser`. One parser for one document; not for use from two threads.
final class GPXParser: NSObject, XMLParserDelegate {
    private enum PointKind { case track, route, waypoint }

    private struct PointBuilder {
        var kind: PointKind
        var point: TrackPoint
        var name: String?
        var details: String?
    }

    private let limits: GPXLimits
    private var failure: GPXError?

    private var creator: String?
    private var fileName: String?
    private var tracks: [GPXTrack] = []
    private var routes: [GPXRoute] = []
    private var waypoints: [GPXWaypoint] = []

    private var stack: [String] = []
    private var skipDepth = 0
    private var text = ""
    private var pointCount = 0

    private var track: GPXTrack?
    private var segment: [TrackPoint]?
    private var route: GPXRoute?
    private var point: PointBuilder?

    // One formatter of each kind for the whole file: making one for every point would dominate the time of a big file.
    private let plainTimes: ISO8601DateFormatter
    private let fractionalTimes: ISO8601DateFormatter

    init(limits: GPXLimits) {
        self.limits = limits
        plainTimes = ISO8601DateFormatter()
        plainTimes.formatOptions = [.withInternetDateTime]
        fractionalTimes = ISO8601DateFormatter()
        fractionalTimes.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func parse(_ data: Data) throws -> GPXFile {
        if Self.hasDocumentType(data) {
            throw GPXError.malformed(line: 1, reason: "a document type declaration is not allowed")
        }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        let succeeded = parser.parse()
        if let failure { throw failure }
        guard succeeded else {
            let reason = parser.parserError?.localizedDescription ?? "unknown error"
            throw GPXError.malformed(line: parser.lineNumber, reason: reason)
        }
        guard stack.isEmpty, sawRoot else { throw GPXError.notGPX }
        return GPXFile(creator: creator, name: fileName, tracks: tracks, routes: routes, waypoints: waypoints)
    }

    private var sawRoot = false

    /// Whether the bytes hold `<!DOCTYPE`, in UTF-8 or in UTF-16 of either byte order (a search of the text would miss the latter). The
    /// search is on bytes and safe against any encoding, so the same text in a comment or a CDATA section is refused as well: a file
    /// that talks about a document type is not worth the risk.
    private static func hasDocumentType(_ data: Data) -> Bool {
        let text = "<!DOCTYPE"
        let patterns = [Data(text.utf8), text.data(using: .utf16LittleEndian), text.data(using: .utf16BigEndian)].compactMap { $0 }
        return patterns.contains { data.range(of: $0) != nil }
    }

    private func fail(_ error: GPXError, _ parser: XMLParser) {
        if failure == nil { failure = error }
        parser.abortParsing()
    }

    // MARK: XMLParserDelegate

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if skipDepth > 0 { skipDepth += 1; return }
        if stack.isEmpty {
            guard elementName == "gpx" else { return fail(.notGPX, parser) }
            creator = attributeDict["creator"]
            sawRoot = true
        }
        if elementName == "extensions" { skipDepth = 1; return }
        stack.append(elementName)
        text = ""
        switch elementName {
        case "trk": track = GPXTrack(segments: [])
        case "trkseg": segment = []
        case "rte": route = GPXRoute(points: [])
        case "trkpt": startPoint(.track, attributeDict, parser)
        case "rtept": startPoint(.route, attributeDict, parser)
        case "wpt": startPoint(.waypoint, attributeDict, parser)
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if skipDepth == 0 { text += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if skipDepth == 0, let string = String(data: CDATABlock, encoding: .utf8) { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if skipDepth > 0 { skipDepth -= 1; return }
        let parent = stack.dropLast().last
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        switch elementName {
        case "ele":
            guard point != nil else { break }
            guard let value = Double(content), value.isFinite else { return fail(.invalidElevation(line: parser.lineNumber, text: content), parser) }
            point?.point.elevation = value
        case "time":
            guard point != nil else { break }
            guard let date = date(from: content) else { return fail(.invalidTime(line: parser.lineNumber, text: content), parser) }
            point?.point.time = date
        case "name":
            if point != nil { point?.name = content }
            else if parent == "trk" { track?.name = content }
            else if parent == "rte" { route?.name = content }
            else if parent == "metadata" || parent == "gpx" { fileName = content }
        case "desc": if point != nil { point?.details = content }
        case "type":
            if point == nil, parent == "trk" { track?.type = content }
        case "trkpt", "rtept", "wpt": finishPoint()
        case "trkseg":
            if let current = segment, !current.isEmpty { track?.segments.append(current) }
            segment = nil
        case "trk":
            if let finished = track { tracks.append(finished) }
            track = nil
        case "rte":
            if let finished = route { routes.append(finished) }
            route = nil
        default: break
        }
        stack.removeLast()
    }

    // A GPX file has no document type, and Foundation reads the content of a local file for an external entity even when it is told not
    // to resolve them. So `parse(_:)` refuses a document type before it starts (which also stops entity expansion, the "billion laughs"),
    // and this is the second guard: an external entity that gets through is not read.
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
        fail(.malformed(line: parser.lineNumber, reason: "an external entity is not allowed"), parser)
        return nil
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if failure == nil { failure = .malformed(line: parser.lineNumber, reason: parseError.localizedDescription) }
    }

    // MARK: Points

    private func startPoint(_ kind: PointKind, _ attributes: [String: String], _ parser: XMLParser) {
        pointCount += 1
        guard pointCount <= limits.maximumPoints else { return fail(.tooManyPoints(limit: limits.maximumPoints), parser) }
        let latText = attributes["lat"], lonText = attributes["lon"]
        guard let latText, let lonText, let latitude = Double(latText), let longitude = Double(lonText),
            Coordinate(latitude: latitude, longitude: longitude).isValid
        else { return fail(.invalidCoordinate(line: parser.lineNumber, latitude: latText, longitude: lonText), parser) }
        point = PointBuilder(kind: kind, point: TrackPoint(latitude: latitude, longitude: longitude))
    }

    private func finishPoint() {
        guard let finished = point else { return }
        point = nil
        switch finished.kind {
        case .track: segment?.append(finished.point)
        case .route: route?.points.append(finished.point)
        case .waypoint: waypoints.append(GPXWaypoint(name: finished.name, details: finished.details, point: finished.point))
        }
    }

    // MARK: Times

    /// An ISO 8601 date and time, with or without fractional seconds. A time with no zone is taken as UTC, as some devices write it.
    ///
    /// The usual forms are read by hand (see ``fastDate(_:)``), because `ISO8601DateFormatter` takes about 40 microseconds for each time,
    /// which is 17 seconds for a file of 450,000 points. Anything else goes to the formatter.
    private func date(from text: String) -> Date? {
        if let date = Self.fastDate(text) { return date }
        if let date = plainTimes.date(from: text) ?? fractionalTimes.date(from: text) { return date }
        // No zone after the time: add one.
        if let time = text.firstIndex(of: "T"), !text[time...].contains(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            return plainTimes.date(from: text + "Z") ?? fractionalTimes.date(from: text + "Z")
        }
        return nil
    }

    /// `YYYY-MM-DDTHH:MM:SS`, then optionally `.` and digits, then optionally `Z` or `+HH:MM` or `-HH:MM` (no zone is UTC). Returns `nil`
    /// for anything else, and for a value out of range (month 13, a 30th of February), so the formatter decides about those.
    static func fastDate(_ text: String) -> Date? {
        var utf8 = text.utf8.makeIterator()
        func digits(_ count: Int) -> Int? {
            var value = 0
            for _ in 0..<count {
                guard let byte = utf8.next(), byte >= 48, byte <= 57 else { return nil }
                value = value * 10 + Int(byte - 48)
            }
            return value
        }
        func expect(_ character: UInt8) -> Bool { utf8.next() == character }
        guard let year = digits(4), expect(45), let month = digits(2), expect(45), let day = digits(2), expect(84),
            let hour = digits(2), expect(58), let minute = digits(2), expect(58), let second = digits(2)
        else { return nil }
        guard (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 60 else { return nil }
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let monthLengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard day <= monthLengths[month - 1] else { return nil }
        // What follows the seconds: a fraction, then a zone.
        var next = utf8.next()
        var fraction = 0.0
        if next == 46 {
            var scale = 0.1
            var count = 0
            next = utf8.next()
            while let byte = next, byte >= 48, byte <= 57 {
                fraction += Double(byte - 48) * scale
                scale /= 10
                count += 1
                next = utf8.next()
            }
            guard count > 0 else { return nil }
        }
        var offset = 0
        if let zone = next {
            switch zone {
            case 90: guard utf8.next() == nil else { return nil }
            case 43, 45:
                guard let hours = digits(2), expect(58), let minutes = digits(2), utf8.next() == nil, hours < 24, minutes < 60 else { return nil }
                offset = (hours * 3600 + minutes * 60) * (zone == 43 ? 1 : -1)
            default: return nil
            }
        }
        // Days since 1970-01-01 of the civil date (Howard Hinnant's algorithm).
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        let days = era * 146_097 + dayOfEra - 719_468
        let seconds = Double(days * 86_400 + hour * 3600 + minute * 60 + second - offset)
        return Date(timeIntervalSince1970: seconds + fraction)
    }
}
