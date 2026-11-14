import Foundation
import Testing

@testable import Tracks

/// Reading GPX: the elements, the versions, the namespaces, the times, and the files that must be refused.
@Suite("GPX file")
struct GPXFileTests {
    private func parse(_ text: String, limits: GPXLimits = .standard) throws -> GPXFile {
        try GPXFile(data: Data(text.utf8), limits: limits)
    }

    private let full = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Test Watch" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata><name>My day</name><time>2026-11-01T06:00:00Z</time></metadata>
          <wpt lat="59.91" lon="10.75"><ele>12.5</ele><name>Water</name><desc>A tap</desc></wpt>
          <rte><name>Planned</name>
            <rtept lat="59.0" lon="10.0"/><rtept lat="59.1" lon="10.1"/></rte>
          <trk><name>Morning run</name><type>running</type>
            <trkseg>
              <trkpt lat="59.9100" lon="10.7500"><ele>10</ele><time>2026-11-01T07:00:00Z</time></trkpt>
              <trkpt lat="59.9101" lon="10.7502"><ele>11.5</ele><time>2026-11-01T07:00:05Z</time></trkpt>
            </trkseg>
            <trkseg>
              <trkpt lat="59.9110" lon="10.7510"><time>2026-11-01T07:10:00.250Z</time></trkpt>
            </trkseg>
            <trkseg></trkseg>
          </trk>
        </gpx>
        """

    @Test("GPX 1.1: a track with segments, a route, a waypoint and the metadata")
    func fullFile() throws {
        let file = try parse(full)
        #expect(file.creator == "Test Watch" && file.name == "My day")
        #expect(file.tracks.count == 1 && file.routes.count == 1 && file.waypoints.count == 1)
        let track = try #require(file.tracks.first)
        #expect(track.name == "Morning run" && track.type == "running")
        #expect(track.segments.map(\.count) == [2, 1], "the empty segment is not kept")
        #expect(track.segments[0][1].elevation == 11.5 && track.segments[1][0].elevation == nil)
        #expect(track.points.count == 3)
        let first = try #require(track.points.first)
        #expect(first.coordinate.latitude == 59.91 && first.coordinate.longitude == 10.75)
        #expect(first.time == ISO8601DateFormatter().date(from: "2026-11-01T07:00:00Z"))
        #expect(abs((track.segments[1][0].time ?? .distantPast).timeIntervalSince1970 - 1_793_517_000.25) < 0.001, "fractional seconds")
        #expect(file.routes[0].name == "Planned" && file.routes[0].points.count == 2 && file.routes[0].points[0].time == nil)
        #expect(file.waypoints[0].name == "Water" && file.waypoints[0].details == "A tap" && file.waypoints[0].point.elevation == 12.5)
    }

    @Test("GPX 1.0, and elements with a namespace prefix, are read the same")
    func versionsAndPrefixes() throws {
        let old = """
            <gpx version="1.0" creator="Old" xmlns="http://www.topografix.com/GPX/1/0">
              <time>2026-11-01T06:00:00Z</time><name>Old file</name>
              <trk><name>T</name><trkseg><trkpt lat="1" lon="2"><ele>3</ele><time>2026-11-01T07:00:00Z</time></trkpt></trkseg></trk>
            </gpx>
            """
        let oldFile = try parse(old)
        #expect(oldFile.name == "Old file" && oldFile.tracks[0].points.count == 1 && oldFile.tracks[0].points[0].elevation == 3)
        let prefixed = """
            <g:gpx xmlns:g="http://www.topografix.com/GPX/1/1" creator="P">
              <g:trk><g:trkseg><g:trkpt lat="1" lon="2"/><g:trkpt lat="1.1" lon="2"/></g:trkseg></g:trk>
            </g:gpx>
            """
        #expect(try parse(prefixed).tracks[0].points.count == 2)
    }

    @Test("The extensions of vendors are skipped, also what looks like a point or a time inside them")
    func extensionsAreSkipped() throws {
        let text = """
            <gpx version="1.1" creator="X" xmlns="http://www.topografix.com/GPX/1/1" xmlns:ns3="http://example.org/ext">
              <trk><name>T</name><extensions><ns3:color>red</ns3:color><trkpt lat="9" lon="9"/></extensions>
                <trkseg>
                  <trkpt lat="1" lon="2"><time>2026-11-01T07:00:00Z</time>
                    <extensions><ns3:hr>150</ns3:hr><time>not a time</time><ele>bad</ele></extensions></trkpt>
                </trkseg></trk>
            </gpx>
            """
        let track = try #require(try parse(text).tracks.first)
        #expect(track.points.count == 1 && track.points[0].coordinate.latitude == 1)
    }

    @Test("Times are read with a zone, an offset, fractions, or no zone (taken as UTC)")
    func timeForms() throws {
        func time(_ text: String) throws -> Date? {
            let gpx = "<gpx><trk><trkseg><trkpt lat=\"1\" lon=\"2\"><time>\(text)</time></trkpt></trkseg></trk></gpx>"
            return try parse(gpx).tracks[0].points[0].time
        }
        let reference = try #require(ISO8601DateFormatter().date(from: "2026-11-01T07:00:00Z"))
        #expect(try time("2026-11-01T07:00:00Z") == reference)
        #expect(try time("2026-11-01T09:00:00+02:00") == reference)
        #expect(try time("2026-11-01T07:00:00") == reference)
        #expect(try time("2026-11-01T07:00:00.000Z") == reference)
        #expect(try time("  2026-11-01T07:00:00Z\n") == reference)
    }

    @Test("A name in CDATA is read, and a point with no time has none")
    func cdataAndMissingTime() throws {
        let gpx = "<gpx><trk><name><![CDATA[Run <1> & more]]></name><trkseg><trkpt lat=\"1\" lon=\"2\"/></trkseg></trk></gpx>"
        let track = try #require(try parse(gpx).tracks.first)
        #expect(track.name == "Run <1> & more" && track.points[0].time == nil)
    }

    // MARK: Refused files

    @Test("Text that is not XML, an XML file that is not GPX, and an empty file are refused with a reason")
    func notGPX() {
        #expect(throws: GPXError.self) { try parse("") }
        #expect(throws: GPXError.self) { try parse("this is not xml") }
        #expect(throws: GPXError.notGPX) { try parse("<html><body/></html>") }
        do { _ = try parse("<gpx><trk><name>x</trk></gpx>"); Issue.record("malformed XML was accepted") } catch let GPXError.malformed(line, _) {
            #expect(line >= 1)
        } catch { Issue.record("wrong error: \(error)") }
    }

    @Test("A point with no position, a position out of range or not a number is refused with the line")
    func badCoordinates() {
        let cases = [
            "<trkpt lon=\"2\"/>", "<trkpt lat=\"1\"/>", "<trkpt lat=\"91\" lon=\"2\"/>", "<trkpt lat=\"1\" lon=\"181\"/>",
            "<trkpt lat=\"abc\" lon=\"2\"/>", "<trkpt lat=\"nan\" lon=\"2\"/>", "<trkpt lat=\"1\" lon=\"inf\"/>",
        ]
        for point in cases {
            let gpx = "<gpx>\n<trk><trkseg>\n\(point)\n</trkseg></trk></gpx>"
            do { _ = try parse(gpx); Issue.record("\(point) was accepted") } catch let GPXError.invalidCoordinate(line, _, _) {
                #expect(line == 3, "\(point)")
            } catch { Issue.record("\(point): wrong error \(error)") }
        }
    }

    @Test("A time or an elevation that cannot be read is refused, not left out")
    func badValues() {
        #expect(throws: GPXError.self) {
            try parse("<gpx><trk><trkseg><trkpt lat=\"1\" lon=\"2\"><time>yesterday</time></trkpt></trkseg></trk></gpx>")
        }
        #expect(throws: GPXError.self) {
            try parse("<gpx><trk><trkseg><trkpt lat=\"1\" lon=\"2\"><ele>high</ele></trkpt></trkseg></trk></gpx>")
        }
        #expect(throws: GPXError.self) {
            try parse("<gpx><trk><trkseg><trkpt lat=\"1\" lon=\"2\"><ele>nan</ele></trkpt></trkseg></trk></gpx>")
        }
    }

    @Test("The limits on the size and on the number of points are enforced")
    func limits() throws {
        let points = (0..<10).map { "<trkpt lat=\"1\" lon=\"\($0)\"/>" }.joined()
        let gpx = "<gpx><trk><trkseg>\(points)</trkseg></trk></gpx>"
        #expect(throws: GPXError.tooManyPoints(limit: 5)) { try parse(gpx, limits: GPXLimits(maximumPoints: 5)) }
        #expect(throws: GPXError.tooManyPoints(limit: 9)) { try parse(gpx, limits: GPXLimits(maximumPoints: 9)) }
        #expect(try parse(gpx, limits: GPXLimits(maximumPoints: 10)).tracks[0].points.count == 10)
        #expect(throws: GPXError.tooLarge(bytes: gpx.utf8.count, limit: 100)) { try parse(gpx, limits: GPXLimits(maximumBytes: 100)) }
        // The waypoints and route points count too.
        let mixed = "<gpx><wpt lat=\"1\" lon=\"1\"/><wpt lat=\"1\" lon=\"2\"/><rte><rtept lat=\"1\" lon=\"3\"/></rte></gpx>"
        #expect(throws: GPXError.tooManyPoints(limit: 2)) { try parse(mixed, limits: GPXLimits(maximumPoints: 2)) }
    }

    @Test("Entity declarations are refused: an external one would read a local file into the name, an internal one can grow without bound")
    func noEntities() {
        let external = """
            <?xml version="1.0"?>
            <!DOCTYPE gpx [<!ENTITY secret SYSTEM "file:///etc/hosts">]>
            <gpx><trk><name>&secret;</name><trkseg><trkpt lat="1" lon="2"/></trkseg></trk></gpx>
            """
        #expect(throws: GPXError.self) { try parse(external) }
        let internalEntity = """
            <?xml version="1.0"?>
            <!DOCTYPE gpx [<!ENTITY a "aaaaaaaaaa"><!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">]>
            <gpx><trk><name>&b;</name><trkseg><trkpt lat="1" lon="2"/></trkseg></trk></gpx>
            """
        #expect(throws: GPXError.self) { try parse(internalEntity) }
        // The same in UTF-16, which a search of the bytes for the text would not find.
        let utf16 = "<?xml version=\"1.0\" encoding=\"UTF-16\"?><!DOCTYPE gpx [<!ENTITY secret SYSTEM \"file:///etc/hosts\">]><gpx><name>&secret;</name></gpx>"
            .data(using: .utf16)!
        #expect(throws: GPXError.self) { try GPXFile(data: utf16) }
    }

    @Test("A file is read from disk, its size is checked before it is read, and a missing file is an error")
    func files() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-\(UUID().uuidString).gpx")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(full.utf8).write(to: url)
        #expect(try GPXFile(contentsOf: url).tracks.count == 1)
        #expect(throws: GPXError.self) { try GPXFile(contentsOf: url, limits: GPXLimits(maximumBytes: 10)) }
        #expect(throws: GPXError.self) { try GPXFile(contentsOf: url.appendingPathExtension("missing")) }
    }

    @Test("Waypoints near a route belong to it, with their distance along it, and none is required")
    func waypointsNearTheRoute() throws {
        let file = try parse(full)
        let route = try #require(file.tracks.first).route()
        // The waypoint at 59.91, 10.75 is at the start of the track; a far one is not.
        var extended = file
        extended.waypoints.append(GPXWaypoint(name: "Far", point: TrackPoint(latitude: 40, longitude: 10)))
        let near = extended.waypoints(near: route, maximumDistance: 100)
        #expect(near.map(\.name) == ["Water"] && near[0].distanceAlong < 20 && near[0].isRequired == false)
    }

    @Test("The hand-written time parser agrees with ISO8601DateFormatter, and leaves odd forms to it")
    func fastTimes() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // Leap days, a century that is not a leap year, a leap century, the end of the year, an offset on each side, midnight.
        for text in [
            "2024-02-29T12:00:00Z", "2000-02-29T00:00:00Z", "2100-02-28T23:59:59Z", "1999-12-31T23:59:59Z", "2026-01-01T00:00:00Z",
            "1970-01-01T00:00:00Z", "2026-11-01T09:00:00+02:00", "2026-11-01T05:30:00-01:30", "2026-03-29T01:59:59+00:00", "1969-07-20T20:17:40Z",
        ] {
            let fast = try #require(GPXParser.fastDate(text), "\(text)")
            let slow = try #require(formatter.date(from: text))
            #expect(fast == slow, "\(text)")
        }
        for text in ["2026-11-01T07:00:00.250Z", "2026-11-01T07:00:00.123456Z", "2026-11-01T07:00:00.5+01:00"] {
            let fast = try #require(GPXParser.fastDate(text))
            let slow = try #require(fractional.date(from: text))
            #expect(abs(fast.timeIntervalSince(slow)) < 0.001, "\(text)")
        }
        #expect(GPXParser.fastDate("2026-11-01T07:00:00") == formatter.date(from: "2026-11-01T07:00:00Z"), "no zone is UTC")
        // What it does not read, it leaves alone, so the formatter (and then the error) decide.
        for text in [
            "2026-13-01T07:00:00Z", "2026-02-30T07:00:00Z", "2026-11-01T24:00:00Z", "2026-11-01T07:60:00Z", "2026-11-01 07:00:00Z", "yesterday", "",
            "2026-11-01T07:00:00.Z", "2026-11-01T07:00:00Zextra", "2026-11-01T07:00:00+0200", "2026-11-01T07:00",
        ] {
            #expect(GPXParser.fastDate(text) == nil, "\(text)")
        }
    }

    @Test("A file of many timed points is read in a few seconds, not tens of seconds")
    func manyTimedPoints() throws {
        let count = 100_000
        var text = "<gpx><trk><trkseg>\n"
        text.reserveCapacity(count * 90)
        for index in 0..<count {
            let seconds = index % 60, minutes = index / 60 % 60, hours = index / 3600 % 24
            text += String(
                format: "<trkpt lat=\"%.6f\" lon=\"10.7\"><ele>10</ele><time>2026-11-01T%02d:%02d:%02dZ</time></trkpt>\n", 59.0 + Double(index) * 1e-6,
                hours, minutes, seconds)
        }
        text += "</trkseg></trk></gpx>"
        let data = Data(text.utf8)
        let clock = ContinuousClock()
        let started = clock.now
        let file = try GPXFile(data: data)
        let elapsed = clock.now - started
        #expect(file.tracks[0].points.count == count && file.tracks[0].points.allSatisfy { $0.time != nil })
        // ISO8601DateFormatter takes about 40 microseconds for each time, which would be 4 s or more here; the hand-written parser needs a
        // fraction of a second. The bound leaves room for a slow machine and still fails if the formatter comes back.
        #expect(elapsed < .seconds(3), "took \(elapsed)")
    }

    @Test("A valid file in UTF-16 is read, and a comment that mentions a document type is refused")
    func utf16AndComments() throws {
        let valid = "<?xml version=\"1.0\" encoding=\"UTF-16\"?><gpx><trk><name>Överste</name><trkseg><trkpt lat=\"1\" lon=\"2\"/></trkseg></trk></gpx>"
        let file = try GPXFile(data: try #require(valid.data(using: .utf16)))
        #expect(file.tracks[0].name == "Överste" && file.tracks[0].points.count == 1)
        // The check is on bytes, so it cannot tell a declaration from a comment about one: both are refused, which is documented.
        #expect(throws: GPXError.self) { try parse("<gpx><!-- <!DOCTYPE --><trk><trkseg><trkpt lat=\"1\" lon=\"2\"/></trkseg></trk></gpx>") }
    }
}
