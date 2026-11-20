import Foundation
import GeoCore
import MapRender
import Testing
import TrackOverlays
import Tracks

@testable import GeoMapKitDemo

/// The GPX files of the library: what is added, what is refused, what is shown and what is remembered.
@MainActor
@Suite("Track library")
struct TrackLibraryTests {
    private struct Rig {
        let root: URL
        let defaults: UserDefaults
        let inbox: URL
    }

    private func rig() throws -> Rig {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-tracks-\(UUID().uuidString)", isDirectory: true)
        let inbox = root.appendingPathComponent("inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        return Rig(root: root, defaults: UserDefaults(suiteName: "geomapkit-tracks-\(UUID().uuidString)")!, inbox: inbox)
    }

    private func library(_ rig: Rig) -> TrackLibrary { TrackLibrary(root: rig.root, defaults: rig.defaults) }

    @discardableResult
    private func write(_ text: String, as name: String, in rig: Rig) throws -> URL {
        let url = rig.inbox.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    /// A run of three points about 222 m long, with times.
    private let run = """
        <gpx version="1.1" creator="Test"><trk><name>Run</name><type>running</type><trkseg>
        <trkpt lat="59.9100" lon="10.7500"><time>2026-11-01T07:00:00Z</time></trkpt>
        <trkpt lat="59.9110" lon="10.7500"><time>2026-11-01T07:01:00Z</time></trkpt>
        <trkpt lat="59.9120" lon="10.7500"><time>2026-11-01T07:02:00Z</time></trkpt>
        </trkseg></trk></gpx>
        """

    @Test("A good file is copied, listed, shown, read and the map is asked to go to it; the same name is not overwritten")
    func addsAGoodFile() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        let tracks = library(r)
        let url = try write(run, as: "Morning run.gpx", in: r)
        let result = await tracks.add([url])
        #expect(result.errors.isEmpty && result.added == ["Morning run.gpx"])
        #expect(tracks.items.map(\.name) == ["Morning run"] && tracks.visible == ["Morning run.gpx"])
        #expect(FileManager.default.fileExists(atPath: tracks.url(of: tracks.items[0]).path))
        #expect(FileManager.default.fileExists(atPath: url.path), "the original is left where it was")
        let summary = try #require(tracks.summaries["Morning run.gpx"])
        #expect(summary.lines == 1 && summary.points == 3 && abs(summary.length - 222.4) < 1 && summary.activities == 1)
        #expect(summary.startDate == ISO8601DateFormatter().date(from: "2026-11-01T07:00:00Z"))
        #expect(tracks.overlays.count == 1)
        #expect(tracks.fit?.box == summary.box && summary.box == BoundingBox(south: 59.91, west: 10.75, north: 59.912, east: 10.75))
        // The same name again gets a name of its own.
        let again = await tracks.add([url])
        #expect(again.added == ["Morning run 2.gpx"] && tracks.items.count == 2 && tracks.overlays.count == 2)
    }

    @Test("A file that is not GPX, is damaged, or has nothing to draw is refused with the reason, and the others are added")
    func refusesBadFiles() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        let tracks = library(r)
        let good = try write(run, as: "good.gpx", in: r)
        let notGPX = try write("hello", as: "notes.txt", in: r)
        let broken = try write("<gpx><trk><name>x</trk></gpx>", as: "broken.gpx", in: r)
        let empty = try write("<gpx><wpt lat=\"1\" lon=\"2\"><name>Only a waypoint</name></wpt></gpx>", as: "empty.gpx", in: r)
        let entity = try write("<?xml version=\"1.0\"?><!DOCTYPE gpx [<!ENTITY a SYSTEM \"file:///etc/hosts\">]><gpx><trk><trkseg><trkpt lat=\"1\" lon=\"2\"/></trkseg></trk></gpx>", as: "entity.gpx", in: r)
        let result = await tracks.add([notGPX, broken, good, empty, entity])
        #expect(result.added == ["good.gpx"] && tracks.items.map(\.name) == ["good"])
        let messages = result.errors.compactMap(\.errorDescription)
        #expect(messages.count == 4)
        #expect(messages.contains { $0.contains("notes.txt") && $0.contains("not a GPX file") })
        #expect(messages.contains { $0.contains("broken.gpx") && $0.contains("line") }, "the line of the error: \(messages)")
        #expect(messages.contains { $0.contains("empty.gpx") && $0.contains("no track or route") })
        #expect(messages.contains { $0.contains("entity.gpx") && $0.contains("document type") })
        let files = try FileManager.default.contentsOfDirectory(atPath: tracks.directory.path).filter { !$0.hasPrefix(".") }
        #expect(files == ["good.gpx"], "nothing refused is copied")
    }

    @Test("A file with a track across the antimeridian is added with the other lines, and says what was not drawn")
    func problemsAreReported() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        let tracks = library(r)
        let mixed = try write("""
            <gpx><trk><name>Fine</name><trkseg><trkpt lat="59.91" lon="10.75"/><trkpt lat="59.92" lon="10.75"/></trkseg></trk>
            <trk><name>Across</name><trkseg><trkpt lat="0" lon="179.9"/><trkpt lat="0" lon="-179.9"/></trkseg></trk></gpx>
            """, as: "mixed.gpx", in: r)
        let result = await tracks.add([mixed])
        #expect(result.errors.isEmpty)
        let summary = try #require(tracks.summaries["mixed.gpx"])
        #expect(summary.lines == 1 && summary.problems.count == 1 && summary.problems[0].contains("Across") && summary.problems[0].contains("antimeridian"))
        let onlyAcross = try write("<gpx><trk><trkseg><trkpt lat=\"0\" lon=\"179.9\"/><trkpt lat=\"0\" lon=\"-179.9\"/></trkseg></trk></gpx>", as: "across.gpx", in: r)
        let refused = await tracks.add([onlyAcross])
        #expect(refused.added.isEmpty && refused.errors.first?.errorDescription?.contains("antimeridian") == true)
    }

    @Test("Tracks, routes and the waypoints beside them of one file are all drawn, in one box")
    func severalLines() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        let tracks = library(r)
        let file = try write("""
            <gpx><wpt lat="59.9101" lon="10.7501"><name>Tap</name></wpt><wpt lat="40" lon="10"><name>Far</name></wpt>
            <rte><name>Plan</name><rtept lat="60.0" lon="11.0"/><rtept lat="60.01" lon="11.0"/></rte>
            <trk><name>Run</name><trkseg><trkpt lat="59.91" lon="10.75"/><trkpt lat="59.92" lon="10.75"/></trkseg></trk></gpx>
            """, as: "both.gpx", in: r)
        await tracks.add([file])
        let summary = try #require(tracks.summaries["both.gpx"])
        #expect(summary.lines == 2 && summary.activities == 0)
        #expect(summary.box == BoundingBox(south: 59.91, west: 10.75, north: 60.01, east: 11.0))
        #expect(tracks.overlays.count == 2)
        let withTap = tracks.overlays.filter { !$0.route.waypoints.isEmpty }
        #expect(withTap.count == 1 && withTap[0].route.waypoints.map(\.name) == ["Tap"], "only the waypoint near the track belongs to it")
    }

    @Test("All tracks are shown or hidden one after the other, and only the ones that need it are touched")
    func showsAndHidesAll() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        let tracks = library(r)
        for name in ["a", "b", "c"] { try write(run, as: "\(name).gpx", in: r) }
        _ = await tracks.add(["a", "b", "c"].map { r.inbox.appendingPathComponent("\($0).gpx") })
        #expect(tracks.visible.count == 3)
        await tracks.setAllVisible(false)
        #expect(tracks.visible.isEmpty && tracks.overlays.isEmpty)
        await tracks.setAllVisible(true)
        #expect(tracks.visible.count == 3 && tracks.overlays.count == 3)
        // A switch for one track does the same as the library's own call.
        let first = try #require(tracks.items.first)
        tracks.request(first, visible: false)
        try await Task.sleep(for: .milliseconds(200))
        #expect(!tracks.visible.contains(first.id) && tracks.visible.count == 2)
    }

    @Test("Showing more tracks than the limit needs the user's word: the limit is a number the screen can test")
    func limit() {
        #expect(TrackLibrary.confirmShowAllAbove == 100)
    }

    @Test("What is shown is remembered, a track that is hidden frees its routes, and showing it reads the file again")
    func visibility() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        let first = library(r)
        await first.add([try write(run, as: "a.gpx", in: r), try write(run, as: "b.gpx", in: r)])
        let b = try #require(first.items.first { $0.id == "b.gpx" })
        await first.setVisible(b, false)
        #expect(first.visible == ["a.gpx"] && first.overlays.count == 1)

        // A new library over the same folder and settings (the next start) shows the same, once the files have been read.
        let second = library(r)
        await second.loadVisible()
        #expect(second.visible == ["a.gpx"] && second.overlays.count == 1)
        await second.setVisible(b, true)
        #expect(second.visible == ["a.gpx", "b.gpx"] && second.overlays.count == 2)
        let ids = second.overlays.map(\.overlayID)
        #expect(Set(ids).count == 2, "every overlay has an id of its own")
    }

    @Test("The lengths of the files that were not added by the app are read for the list, without drawing them")
    func summariesOfExistingFiles() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        let tracks = library(r)
        try FileManager.default.createDirectory(at: tracks.directory, withIntermediateDirectories: true)
        try Data(run.utf8).write(to: tracks.directory.appendingPathComponent("dropped in.gpx"))
        try Data("not gpx".utf8).write(to: tracks.directory.appendingPathComponent("damaged.gpx"))
        tracks.reload()
        #expect(tracks.items.count == 2 && tracks.summaries.isEmpty)
        await tracks.loadSummaries()
        #expect(tracks.summaries["dropped in.gpx"]?.points == 3 && tracks.overlays.isEmpty && tracks.visible.isEmpty)
        #expect(tracks.failures["damaged.gpx"]?.contains("damaged.gpx") == true && tracks.summaries["damaged.gpx"] == nil)
    }

    @Test("A track is removed with its file, and one that disappears from the folder is no longer shown")
    func removing() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        let tracks = library(r)
        await tracks.add([try write(run, as: "a.gpx", in: r), try write(run, as: "b.gpx", in: r)])
        let a = try #require(tracks.items.first { $0.id == "a.gpx" })
        try tracks.delete(a)
        #expect(tracks.items.map(\.id) == ["b.gpx"] && tracks.visible == ["b.gpx"] && tracks.summaries["a.gpx"] == nil)
        #expect(!FileManager.default.fileExists(atPath: tracks.directory.appendingPathComponent("a.gpx").path))
        // Removed outside the app.
        try FileManager.default.removeItem(at: tracks.directory.appendingPathComponent("b.gpx"))
        tracks.reload()
        #expect(tracks.items.isEmpty && tracks.visible.isEmpty && tracks.overlays.isEmpty)
        // And that is remembered: the next start does not try to show it.
        #expect(library(r).visible.isEmpty)
    }

    @Test("What was read of a file is kept for the next start, and a file that changed is read again")
    func summariesAreKept() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        let first = library(r)
        await first.add([try write(run, as: "a.gpx", in: r)])
        let item = try #require(first.items.first)
        let original = try #require(first.summaries["a.gpx"])
        await first.setVisible(item, false)
        #expect(FileManager.default.fileExists(atPath: first.directory.appendingPathComponent(".summaries.json").path))
        #expect(first.items.map(\.id) == ["a.gpx"], "the file of the cache is not a track")

        // The file is replaced by garbage of the same size and date: if the next start read it, it would fail.
        let url = first.url(of: item)
        let modified = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
        try Data(repeating: 0x78, count: Int(item.bytes)).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        let second = library(r)
        await second.loadSummaries()
        #expect(second.summaries["a.gpx"] == original && second.failures.isEmpty, "the summary came from the cache, the file was not read")

        // A file of another size is another file: it is read, and it is not GPX.
        try Data("not gpx at all".utf8).write(to: url)
        let third = library(r)
        await third.loadSummaries()
        #expect(third.summaries["a.gpx"] == nil && third.failures["a.gpx"] != nil)
    }

    @Test("A track that is removed while its file is being read leaves nothing behind")
    func removedWhileReading() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        let tracks = library(r)
        try FileManager.default.createDirectory(at: tracks.directory, withIntermediateDirectories: true)
        try Data(run.utf8).write(to: tracks.directory.appendingPathComponent("a.gpx"))
        tracks.reload()
        let item = try #require(tracks.items.first)
        async let reading: Void = tracks.loadSummaries()
        try tracks.delete(item)
        await reading
        #expect(tracks.items.isEmpty && tracks.summaries.isEmpty && tracks.failures.isEmpty)
    }

    // MARK: Fitting the map to a track

    @Test("The map is fitted to the height of a track as well as to its width")
    func fitsInBothDirections() {
        let size = CGSize(width: 600, height: 400)
        let padding = 40.0
        /// Whether both corners of the box are inside the view with the padding, when the map is centred on the box.
        func fits(_ box: BoundingBox, at zoom: Double) -> Bool {
            let view = MapViewport(center: MapLibrary.mercatorMiddle(of: box), zoom: zoom, width: size.width, height: size.height)
            let corners = [
                Coordinate(latitude: box.north, longitude: box.west), Coordinate(latitude: box.south, longitude: box.east),
            ].map(view.screenPoint(for:))
            return corners.allSatisfy {
                $0.x >= padding - 0.5 && $0.x <= size.width - padding + 0.5 && $0.y >= padding - 0.5 && $0.y <= size.height - padding + 0.5
            }
        }
        let limits = 2.0...20.0
        // A track that runs north to south, about 22 km, with almost no longitude: it was fitted by its width, at the highest zoom.
        let tall = BoundingBox(south: 59.80, west: 10.7500, north: 60.00, east: 10.7501)
        let tallZoom = MapLibrary.zoom(fitting: tall, in: size, limits: limits)
        #expect(tallZoom < 13 && fits(tall, at: tallZoom) && !fits(tall, at: tallZoom + 0.5), "zoom \(tallZoom)")
        // A wide one is fitted by its width.
        let wide = BoundingBox(south: 59.90, west: 10.0, north: 59.9001, east: 11.0)
        let wideZoom = MapLibrary.zoom(fitting: wide, in: size, limits: limits)
        #expect(fits(wide, at: wideZoom) && !fits(wide, at: wideZoom + 0.5))
        // Nearly square, in a view that is wider than it is tall: the height decides.
        let square = BoundingBox(south: 59.90, west: 10.70, north: 59.95, east: 10.78)
        let squareZoom = MapLibrary.zoom(fitting: square, in: size, limits: limits)
        #expect(fits(square, at: squareZoom) && !fits(square, at: squareZoom + 0.3))
        // The middle of a tall box is halfway down on the map, not halfway in latitude.
        let tallMiddle = MapLibrary.mercatorMiddle(of: BoundingBox(south: 50, west: 10, north: 70, east: 12))
        #expect(tallMiddle.longitude == 11 && tallMiddle.latitude > 61.4 && tallMiddle.latitude < 61.8, "\(tallMiddle)")
        // A single point goes to the highest zoom, a box larger than the world to the lowest, and a view with no room still gives a zoom.
        #expect(MapLibrary.zoom(fitting: BoundingBox(south: 59, west: 10, north: 59, east: 10), in: size, limits: limits) == 20)
        #expect(MapLibrary.zoom(fitting: BoundingBox(south: -80, west: -180, north: 80, east: 180), in: size, limits: limits) == 2)
        #expect(limits.contains(MapLibrary.zoom(fitting: square, in: .zero, limits: limits)))
    }
}
