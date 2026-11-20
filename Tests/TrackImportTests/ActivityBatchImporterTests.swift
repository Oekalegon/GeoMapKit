import FeatureStore
import Foundation
import GeoCore
import Testing
import Tracks

@testable import TrackImport
@testable import TrackStorage

@Suite("Activity batch importer")
struct ActivityBatchImporterTests {
    private func importer(_ store: TrackStore, matchedWith: Int = 1, policy: CategoryPolicy = CategoryPolicy()) throws -> ActivityBatchImporter {
        ActivityBatchImporter(
            networks: ActivityNetworks(source: try ImportFixtures.map()), store: store, mapID: "test", policy: policy, matchedWith: matchedWith)
    }

    private func requests(_ directory: URL) throws -> [ImportRequest] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }.map { .gpx(at: $0) }
    }

    @Test("Files are read, the category comes from the name, and orienteering is not matched")
    func importsFiles() async throws {
        let directory = try ImportFixtures.folder([
            "run.gpx": ImportFixtures.gpx(name: "Morning run"), "ol.gpx": ImportFixtures.gpx(name: "OL training Epe", first: 100_000),
        ])
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TrackStore(url: nil)
        // The standard policy suggests nothing: both are runs. An app that has the exception opts in.
        let plain = await (try importer(store)).run(try requests(directory))
        #expect(plain.categories == ["run": 2])
        let other = try TrackStore(url: nil)
        let report = await (try importer(other, policy: .orienteering)).run(try requests(directory))
        #expect(report.added == 2 && report.replaced == 0 && report.skipped == 0 && report.failures.isEmpty && !report.cancelled)
        #expect(report.categories == ["run": 1, "orienteering": 1])
        let categories = try await other.activityCategories()
        let runCounts = try await other.counts(ways: [7], categories: ["run"])
        let olCounts = try await other.counts(ways: [7], categories: ["orienteering"])
        #expect(categories == ["run": 1, "orienteering": 1] && !runCounts.isEmpty && olCounts.isEmpty)
    }

    @Test("A second run skips what is in the store; other rules make it again")
    func repeated() async throws {
        let directory = try ImportFixtures.folder(["run.gpx": ImportFixtures.gpx(name: "Run")])
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TrackStore(url: nil)
        _ = await (try importer(store)).run(try requests(directory))
        let again = await (try importer(store)).run(try requests(directory))
        #expect(again.added == 0 && again.skipped == 1 && again.replaced == 0)
        let newer = await (try importer(store, matchedWith: 2)).run(try requests(directory))
        #expect(newer.replaced == 1 && newer.skipped == 0)
        let count = try await store.activityCount()
        #expect(count == 1)
    }

    @Test("A bulk change retags the activities it picks and no others, and a later run keeps the choice")
    func change() async throws {
        let directory = try ImportFixtures.folder([
            "a.gpx": ImportFixtures.gpx(name: "Run one"), "b.gpx": ImportFixtures.gpx(name: "Run two", first: 100 * 86_400),
        ])
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TrackStore(url: nil)
        let batch = try importer(store)
        _ = await batch.run(try requests(directory))
        // The second file started 100 days after the first.
        let late = ImportFixtures.start.addingTimeInterval(50 * 86_400)...ImportFixtures.start.addingTimeInterval(200 * 86_400)
        let change = CategoryChange(selection: ActivitySelection(dates: late), category: "orienteering")
        let report = await batch.run(try requests(directory), change: change)
        #expect(report.replaced == 1 && report.skipped == 1 && report.added == 0)
        let categories = try await store.activityCategories()
        #expect(categories == ["run": 1, "orienteering": 1])
        // Without the change the choice stays.
        let plain = await batch.run(try requests(directory))
        let after = try await store.activityCategories()
        #expect(plain.skipped == 2 && after == ["run": 1, "orienteering": 1])
    }

    @Test("A file that cannot be read, and a track with no times, are reported and the run goes on")
    func failures() async throws {
        let directory = try ImportFixtures.folder([
            "good.gpx": ImportFixtures.gpx(name: "Run"), "bad.gpx": "not xml at all", "route.gpx": ImportFixtures.gpx(name: "Plan", timed: false),
        ])
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TrackStore(url: nil)
        let report = await (try importer(store)).run(try requests(directory))
        #expect(report.added == 1)
        // A file that cannot be read is a failure; a track with no times is not an activity, which is not an error.
        #expect(report.failures.map(\.source) == ["bad.gpx"] && report.failures.allSatisfy { $0.activityID == nil })
        #expect(report.notActivities.map(\.source) == ["route.gpx"])
    }

    @Test("A run that is cancelled starts nothing more, says so, and leaves the store as it was")
    func cancelled() async throws {
        let directory = try ImportFixtures.folder(["a.gpx": ImportFixtures.gpx(name: "Run")])
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TrackStore(url: nil)
        let batch = try importer(store)
        let all = try requests(directory)
        let report = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await batch.run(all)
        }.value
        let count = try await store.activityCount()
        #expect(report.cancelled && report.handled == 0 && count == 0)
    }

    @Test("Progress is reported once for each request, up to the total")
    func progress() async throws {
        let directory = try ImportFixtures.folder(["a.gpx": ImportFixtures.gpx(name: "A"), "b.gpx": ImportFixtures.gpx(name: "B", first: 100_000)])
        defer { try? FileManager.default.removeItem(at: directory) }
        let seen = Seen()
        let store = try TrackStore(url: nil)
        _ = await (try importer(store)).run(try requests(directory)) { seen.add($0) }
        let all = seen.all
        #expect(all.map(\.finished).sorted() == [1, 2] && all.allSatisfy { $0.total == 2 })
    }

    @Test("Networks are kept for tracks in the same area, and a box that is too large is refused")
    func networks() async throws {
        let provider = ActivityNetworks(source: try ImportFixtures.map())
        let one = try await provider.network(for: BoundingBox(south: 60.0, west: 10.0, north: 60.0, east: 10.01))
        let two = try await provider.network(for: BoundingBox(south: 60.001, west: 10.002, north: 60.002, east: 10.004))
        #expect(one.edges.count == 1 && two.edges.count == 1)
        await #expect(throws: (any Error).self) { _ = try await provider.network(for: BoundingBox(south: 40, west: -20, north: 70, east: 30)) }
    }

    @Test("A run that is cancelled while a source is being handled says so, also when every request was started")
    func cancelledInTheMiddle() async throws {
        let store = try TrackStore(url: nil)
        let batch = try importer(store)
        let one = try ActivityTrack(id: "x", points: [TrackPoint(coordinate: Coordinate(latitude: 60, longitude: 10), time: ImportFixtures.start), TrackPoint(coordinate: Coordinate(latitude: 60, longitude: 10.001), time: ImportFixtures.start.addingTimeInterval(60))], tags: [:])
        let request = ImportRequest(source: "two") {
            // The task of the request is cancelled after it has been read, with its activities still to do.
            withUnsafeCurrentTask { $0?.cancel() }
            return ImportRequest.Loaded(activities: [one, one])
        }
        let report = await batch.run([request])
        #expect(report.cancelled && report.handled == 0)
    }

    @Test("Retagging changes the activities that are in the store and picked, and adds nothing that is not there")
    func retag() async throws {
        let directory = try ImportFixtures.folder(["a.gpx": ImportFixtures.gpx(name: "Run one"), "b.gpx": ImportFixtures.gpx(name: "Run two", first: 100_000)])
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TrackStore(url: nil)
        let batch = try importer(store)
        let all = try requests(directory)
        _ = await batch.run([all[0]])
        let change = CategoryChange(selection: ActivitySelection(), category: "orienteering")
        let report = await batch.retag(all, change: change)
        #expect(report.replaced == 1 && report.added == 0 && report.skipped == 1)
        let categories = try await store.activityCategories()
        #expect(categories == ["orienteering": 1])
    }

    @Test("A change by the place of the start picks the activities that started in the box")
    func changeByPlace() async throws {
        let directory = try ImportFixtures.folder(["a.gpx": ImportFixtures.gpx(name: "Run")])
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TrackStore(url: nil)
        let batch = try importer(store)
        _ = await batch.run(try requests(directory))
        let near = BoundingBox(south: 59.99, west: 9.99, north: 60.01, east: 10.01)
        let far = BoundingBox(south: 50, west: 0, north: 51, east: 1)
        let missed = await batch.retag(try requests(directory), change: CategoryChange(selection: ActivitySelection(startsIn: far), category: "x"))
        #expect(missed.replaced == 0 && missed.skipped == 1)
        let hit = await batch.retag(try requests(directory), change: CategoryChange(selection: ActivitySelection(startsIn: near), category: "x"))
        #expect(hit.replaced == 1)
    }

    @Test("The same activity in two files of one run is handled once, also with two jobs")
    func duplicates() async throws {
        let text = ImportFixtures.gpx(name: "Run")
        let directory = try ImportFixtures.folder(["a.gpx": text, "b.gpx": text, "c.gpx": text])
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TrackStore(url: nil)
        let report = await (try importer(store)).run(try requests(directory))
        #expect(report.added == 1 && report.skipped == 2 && report.replaced == 0)
        let count = try await store.activityCount()
        #expect(count == 1)
    }

    @Test("A GPX file gives an activity for each track with times, the tags of the file, and a problem for a route")
    func gpxRequest() throws {
        let one = ImportFixtures.gpx(name: "First")
        let second = ImportFixtures.gpx(name: "Second", first: 100_000)
        func body(_ text: String) -> String { text.components(separatedBy: "<trk>")[1].components(separatedBy: "</trk>")[0] }
        let route = "<rte><name>Plan</name><rtept lat=\"60\" lon=\"10\"/><rtept lat=\"60\" lon=\"10.001\"/></rte>"
        let file = "<?xml version=\"1.0\"?><gpx version=\"1.1\" creator=\"t\" xmlns=\"http://www.topografix.com/GPX/1/1\"><trk><type>running</type>\(body(one))</trk><trk>\(body(second))</trk>\(route)</gpx>"
        let directory = try ImportFixtures.folder(["two.gpx": file])
        defer { try? FileManager.default.removeItem(at: directory) }
        let loaded = try ImportRequest.gpx(at: directory.appendingPathComponent("two.gpx")).load()
        #expect(loaded.activities.count == 2 && loaded.activities.allSatisfy { $0.tags["gpx.file"] == .string("two.gpx") })
        #expect(loaded.activities[0].tags["gpx.name"] == .string("First") && loaded.activities[0].tags["gpx.type"] == .string("running"))
        #expect(loaded.problems.count == 1 && loaded.problems[0].hasPrefix("Plan"))
    }
}

/// Collects progress from any thread.
final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ImportProgress] = []
    func add(_ value: ImportProgress) { lock.withLock { values.append(value) } }
    var all: [ImportProgress] { lock.withLock { values } }
}