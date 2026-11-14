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
}
