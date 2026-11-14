import Foundation
import Testing
import ToolSupport

@testable import ToolCommands

@Suite("Track info command")
struct TrackInfoCommandTests {
    private let gpx = """
        <?xml version="1.0"?>
        <gpx version="1.1" creator="Test">
          <metadata><name>A day</name></metadata>
          <wpt lat="59.9101" lon="10.7501"><name>Tap</name></wpt>
          <wpt lat="40" lon="10"><name>Far</name></wpt>
          <rte><name>Planned</name><rtept lat="59" lon="10"/><rtept lat="59.01" lon="10"/></rte>
          <trk><name>Run</name><type>running</type><trkseg>
            <trkpt lat="59.9100" lon="10.7500"><time>2026-11-01T07:00:00Z</time></trkpt>
            <trkpt lat="59.9110" lon="10.7500"><time>2026-11-01T07:01:00Z</time></trkpt>
            <trkpt lat="59.9120" lon="10.7500"><time>2026-11-01T07:02:03Z</time></trkpt>
          </trkseg></trk>
          <trk><name>Drawn</name><trkseg><trkpt lat="59" lon="10"/><trkpt lat="59.01" lon="10"/></trkseg></trk>
        </gpx>
        """

    private func write(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-\(UUID().uuidString).gpx")
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test("the report lists the tracks with their activity verdict, the routes and the waypoints")
    func report() throws {
        let url = try write(gpx)
        defer { try? FileManager.default.removeItem(at: url) }
        let report = try ToolRunner.trackInfo(url: url)
        #expect(report.creator == "Test" && report.name == "A day" && report.tracks.count == 2 && report.routes.count == 1)
        #expect(report.waypoints == 2 && report.waypointsNearATrack == 1)
        let run = report.tracks[0]
        #expect(run.type == "running" && run.points == 3 && run.segments == 1 && run.timedFraction == 1)
        #expect(abs((run.length ?? 0) - 222.4) < 1)
        guard case .success(let activity) = run.activity else { Issue.record("the run is no activity"); return }
        #expect(activity.duration == 123)
        guard case .failure(.tooFewTimes) = report.tracks[1].activity else { Issue.record("a track with no times is an activity"); return }
        #expect(abs((report.routes[0].length ?? 0) - 1_112) < 2)
    }

    @Test("the text says what is an activity, with the reason when it is not")
    func text() throws {
        let url = try write(gpx)
        defer { try? FileManager.default.removeItem(at: url) }
        let text = ReportFormatter.text(for: try ToolRunner.trackInfo(url: url))
        #expect(text.contains("Tracks:    2") && text.contains("\"Run\" (running): 3 points in 1 segment, 0.22 km"))
        #expect(text.contains("Activity: yes, started 2026-11-01T07:00:00Z, 0:02:03, 0.22 km, id gpx-"))
        #expect(text.contains("Activity: no, Only 0 % of the points have a time"))
        #expect(text.contains("Routes:    1") && text.contains("\"Planned\": 2 points, 1.11 km"))
        #expect(text.contains("Waypoints: 2 (1 within 100 m of a track)"))
    }

    @Test("a file that is not GPX is an error with the file name")
    func notGPX() throws {
        let url = try write("<html/>")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: ToolError.self) { try ToolRunner.trackInfo(url: url) }
        #expect(throws: ToolError.self) { try ToolRunner.trackInfo(url: url.appendingPathExtension("missing")) }
    }
}
