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

    /// Whether the bytes hold `<!DOCTYPE`, in UTF-8 or in UTF-16 of either byte order (a search of the text would miss the latter).
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
    private func date(from text: String) -> Date? {
        if let date = plainTimes.date(from: text) ?? fractionalTimes.date(from: text) { return date }
        // No zone after the time: add one.
        if let time = text.firstIndex(of: "T"), !text[time...].contains(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            return plainTimes.date(from: text + "Z") ?? fractionalTimes.date(from: text + "Z")
        }
        return nil
    }
}
