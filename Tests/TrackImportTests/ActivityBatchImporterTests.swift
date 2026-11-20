import FeatureStore
import Foundation
import GeoCore
import Testing
import Tracks

@testable import TrackImport
@testable import TrackStorage

@Suite("Activity batch importer")
struct ActivityBatchImporterTests {
    private func importer(_ store: TrackStore, matchedWith: Int = 1) throws -> ActivityBatchImporter {
        ActivityBatchImporter(networks: ActivityNetworks(source: try ImportFixtures.map()), store: store, mapID: "test", matchedWith: matchedWith)
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
        let report = await (try importer(store)).run(try requests(directory))
        #expect(report.added == 2 && report.replaced == 0 && report.skipped == 0 && report.failures.isEmpty && !report.cancelled)
        #expect(report.categories == ["run": 1, "orienteering": 1])
        let categories = try await store.activityCategories()
        let runCounts = try await store.counts(ways: [7], categories: ["run"])
        let olCounts = try await store.counts(ways: [7], categories: ["orienteering"])
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
        #expect(Set(report.failures.map(\.source)) == ["bad.gpx", "route.gpx"] && report.failures.allSatisfy { $0.activityID == nil })
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
}

/// Collects progress from any thread.
final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ImportProgress] = []
    func add(_ value: ImportProgress) { lock.withLock { values.append(value) } }
    var all: [ImportProgress] { lock.withLock { values } }
}
