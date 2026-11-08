import Foundation
import GeoCore
import Testing

@testable import Regions

/// Planning and fetching, with a fake server.
@Suite("SourceManager")
struct SourceManagerTests {
    private let norwayURL = URL(string: "https://download.example.org/europe/norway-latest.osm.pbf")!
    private let swedenURL = URL(string: "https://download.example.org/europe/sweden-latest.osm.pbf")!

    private func region(_ id: String, _ url: URL) -> SourceRegion {
        let ring = [Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: 1), Coordinate(latitude: 1, longitude: 1)]
        return SourceRegion(id: id, name: id.capitalized, parentID: nil, pbfURL: url, outline: [RegionPolygon(outer: ring)])
    }

    private func selection() -> RegionSelection {
        RegionSelection(regions: [region("norway", norwayURL), region("sweden", swedenURL)], coveredShare: 0.97)
    }

    private struct Setup {
        let manager: SourceManager
        let server: FakeServer
        let clock: TestClock
        let directory: URL
    }

    private func setup(space: Int64? = 100_000_000_000) async -> Setup {
        let server = FakeServer()
        await server.put(norwayURL, Data((0..<5000).map { UInt8($0 % 251) }))
        await server.put(swedenURL, Data((0..<3000).map { UInt8($0 % 241) }), etag: "\"s1\"")
        let clock = TestClock()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-manager-\(UUID().uuidString)")
        let cache = SourceCache(directory: directory, now: { clock.now }, availableCapacity: { _ in space })
        return Setup(manager: SourceManager(cache: cache, downloader: FakeDownloader(server: server)), server: server, clock: clock, directory: directory)
    }

    @Test("A plan for files that are not cached has their sizes from the server and downloads nothing")
    func planMissing() async throws {
        let s = await setup()
        defer { try? FileManager.default.removeItem(at: s.directory) }
        let plan = try await s.manager.plan(for: selection())
        #expect(plan.items.map(\.region.id) == ["norway", "sweden"])
        #expect(plan.items.map(\.action) == [.download, .download] && plan.items.map(\.size) == [5000, 3000])
        #expect(plan.bytesToDownload == 8000 && plan.needsDownload && !plan.hasUnknownSizes && plan.coveredShare == 0.97)
        #expect(await s.server.requests(containing: "GET").isEmpty, "the plan only asks")
        #expect(!FileManager.default.fileExists(atPath: s.directory.path), "and writes nothing")
    }

    @Test("Fetching downloads the files in plan order, and the next plan uses the cache without asking the server")
    func fetch() async throws {
        let s = await setup()
        defer { try? FileManager.default.removeItem(at: s.directory) }
        let plan = try await s.manager.plan(for: selection())
        let reported = ProgressLog()
        let files = try await s.manager.fetch(plan) { id, bytes, total in reported.add(id, bytes, total) }
        #expect(files.map(\.lastPathComponent) == ["norway.osm.pbf", "sweden.osm.pbf"])
        let norwayData = await s.server.data(norwayURL), swedenData = await s.server.data(swedenURL)
        #expect(try Data(contentsOf: files[0]) == norwayData)
        #expect(try Data(contentsOf: files[1]) == swedenData)
        #expect(reported.last("norway")?.0 == 5000 && reported.last("norway")?.1 == 5000)
        #expect(reported.last("sweden")?.0 == 3000 && reported.last("sweden")?.1 == 3000)

        let before = await s.server.requests(containing: "").count
        let again = try await s.manager.plan(for: selection())
        #expect(again.items.map(\.action) == [.useCached, .useCached] && !again.needsDownload && again.bytesToDownload == 0)
        #expect(await s.server.requests(containing: "").count == before, "a current file costs no request")
    }

    @Test("A file older than the time limit is asked about with its ETag; unchanged only renews the check")
    func staleNotModified() async throws {
        let s = await setup()
        defer { try? FileManager.default.removeItem(at: s.directory) }
        _ = try await s.manager.fetch(try await s.manager.plan(for: selection()))
        s.clock.advance(days: 31)
        let plan = try await s.manager.plan(for: selection())
        #expect(plan.items.map(\.action) == [.useCached, .useCached])
        #expect(await s.server.requests(containing: "if-none-match \"v1\"").count == 1)
        #expect(await s.server.requests(containing: "GET").count == 2, "no new download")
        // The check was recorded: a month later is needed before it is asked again.
        let asked = await s.server.requests(containing: "HEAD").count
        _ = try await s.manager.plan(for: selection())
        #expect(await s.server.requests(containing: "HEAD").count == asked)
    }

    @Test("A changed file is an update: the old file stays until the new one is complete, then is replaced")
    func staleChanged() async throws {
        let s = await setup()
        defer { try? FileManager.default.removeItem(at: s.directory) }
        _ = try await s.manager.fetch(try await s.manager.plan(for: selection()))
        let newData = Data(repeating: 42, count: 6000)
        await s.server.put(norwayURL, newData, etag: "\"v2\"")
        s.clock.advance(days: 40)
        let plan = try await s.manager.plan(for: selection())
        #expect(plan.items.map(\.action) == [.update, .useCached])
        #expect(plan.items[0].size == 6000 && plan.bytesToDownload == 6000)

        await s.server.cutNextDownload(after: 2000)
        await #expect(throws: (any Error).self) { try await s.manager.fetch(plan) }
        let old = s.manager.cache.fileURL(forRegionID: "norway")
        #expect(try Data(contentsOf: old).count == 5000, "the old file is intact after a failed update")
        #expect(s.manager.cache.partialDownload(regionID: "norway")?.bytes == 2000)

        // The next plan finds the part and the fetch continues after it.
        let resumed = try await s.manager.plan(for: selection())
        #expect(resumed.items[0].alreadyDownloaded == 2000 && resumed.bytesToDownload == 4000)
        _ = try await s.manager.fetch(resumed)
        #expect(try Data(contentsOf: old) == newData)
        #expect(await s.server.requests(containing: "GET").last == "GET \(norwayURL) from 2000 if-range \"v2\"")
        #expect(s.manager.cache.status(ofRegionID: "norway").record?.etag == "\"v2\"")
    }

    @Test("An interrupted download continues where it stopped; if the file changed meanwhile it starts again")
    func resume() async throws {
        let s = await setup()
        defer { try? FileManager.default.removeItem(at: s.directory) }
        let one = RegionSelection(regions: [region("norway", norwayURL)], coveredShare: 1)
        let plan = try await s.manager.plan(for: one)
        await s.server.cutNextDownload(after: 1400)
        await #expect(throws: (any Error).self) { try await s.manager.fetch(plan) }
        #expect(s.manager.cache.partialDownload(regionID: "norway")?.bytes == 1400)
        #expect(s.manager.cache.status(ofRegionID: "norway").status == .missing)

        let resumed = try await s.manager.plan(for: one)
        _ = try await s.manager.fetch(resumed)
        let norwayNow = await s.server.data(norwayURL)
        #expect(try Data(contentsOf: s.manager.cache.fileURL(forRegionID: "norway")) == norwayNow)
        #expect(await s.server.requests(containing: "GET").last == "GET \(norwayURL) from 1400 if-range \"v1\"")

        // A second source whose file changes between the interrupted download and the next one.
        try s.manager.cache.remove(regionID: "norway")
        let plan2 = try await s.manager.plan(for: one)
        await s.server.cutNextDownload(after: 1000)
        await #expect(throws: (any Error).self) { try await s.manager.fetch(plan2) }
        let changed = Data(repeating: 5, count: 4000)
        await s.server.put(norwayURL, changed, etag: "\"v9\"")
        let plan3 = try await s.manager.plan(for: one)
        #expect(plan3.items[0].alreadyDownloaded == 0, "the part belongs to another version")
        _ = try await s.manager.fetch(plan3)
        #expect(try Data(contentsOf: s.manager.cache.fileURL(forRegionID: "norway")) == changed)
    }

    @Test("A server that does not support ranges sends the whole file and the part is emptied")
    func noRanges() async throws {
        let s = await setup()
        defer { try? FileManager.default.removeItem(at: s.directory) }
        let one = RegionSelection(regions: [region("sweden", swedenURL)], coveredShare: 1)
        let plan = try await s.manager.plan(for: one)
        await s.server.cutNextDownload(after: 900)
        await #expect(throws: (any Error).self) { try await s.manager.fetch(plan) }
        await s.server.setSupportsRange(false)
        _ = try await s.manager.fetch(try await s.manager.plan(for: one))
        let swedenNow = await s.server.data(swedenURL)
        #expect(try Data(contentsOf: s.manager.cache.fileURL(forRegionID: "sweden")) == swedenNow)
    }

    @Test("Too little free space is refused before anything is downloaded")
    func space() async throws {
        let s = await setup(space: 1_000_000)
        defer { try? FileManager.default.removeItem(at: s.directory) }
        let plan = try await s.manager.plan(for: selection())
        await #expect(throws: SourceError.notEnoughSpace(needed: 8000 + SourceManager.spareBytes, available: 1_000_000)) {
            try await s.manager.fetch(plan)
        }
        #expect(await s.server.requests(containing: "GET").isEmpty)
    }

    @Test("The size the server gives with the download counts, not the size in the plan")
    func sizeAtDownloadTime() async throws {
        let s = await setup()
        defer { try? FileManager.default.removeItem(at: s.directory) }
        let one = RegionSelection(regions: [region("sweden", swedenURL)], coveredShare: 1)
        let plan = try await s.manager.plan(for: one)
        // The server's file shrinks after the plan: the download has fewer bytes than the plan said, but the server's
        // own size at download time is what counts, so it is installed with that size.
        await s.server.put(swedenURL, Data(repeating: 1, count: 2000), etag: "\"s2\"")
        _ = try await s.manager.fetch(plan)
        #expect(s.manager.cache.status(ofRegionID: "sweden").record?.size == 2000)
    }

    /// A downloader that claims a size but delivers half of it, as a connection that closes politely would.
    private struct ShortDownloader: Downloader {
        func metadata(of url: URL, ifNoneMatch etag: String?) async throws -> RemoteMetadata {
            .info(RemoteFileInfo(size: 1000, etag: "\"x\""))
        }
        func download(
            from url: URL, to file: URL, resumeFrom offset: Int64, ifRange etag: String?, progress: @Sendable (Int64) -> Void
        ) async throws -> RemoteFileInfo {
            try Data(repeating: 1, count: 500).write(to: file)
            return RemoteFileInfo(size: 1000, etag: "\"x\"")
        }
    }

    @Test("A download that ends short is not installed, and the part stays to be continued")
    func shortDownload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-manager-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = SourceManager(cache: SourceCache(directory: directory, availableCapacity: { _ in nil }), downloader: ShortDownloader())
        let one = RegionSelection(regions: [region("norway", norwayURL)], coveredShare: 1)
        let plan = try await manager.plan(for: one)
        await #expect(throws: SourceError.incompleteDownload(region: "norway", expected: 1000, received: 500)) {
            try await manager.fetch(plan)
        }
        #expect(manager.cache.status(ofRegionID: "norway").status == .missing)
        #expect(manager.cache.partialDownload(regionID: "norway")?.bytes == 500)
    }

    @Test("A file that cannot be checked is used, with the reason; a missing file cannot be planned offline")
    func offline() async throws {
        let s = await setup()
        defer { try? FileManager.default.removeItem(at: s.directory) }
        _ = try await s.manager.fetch(try await s.manager.plan(for: selection()))
        s.clock.advance(days: 60)
        await s.server.setOffline(true)
        let plan = try await s.manager.plan(for: selection())
        #expect(plan.items.map(\.action) == [.useCached, .useCached] && plan.items.allSatisfy { $0.checkFailure != nil })
        #expect(!plan.needsDownload)

        let other = RegionSelection(regions: [region("finland", URL(string: "https://download.example.org/europe/finland-latest.osm.pbf")!)], coveredShare: 1)
        await #expect(throws: (any Error).self) { try await s.manager.plan(for: other) }
    }

    @Test("A file whose size the server does not give is planned with unknown size and installed as it arrives")
    func unknownSize() async throws {
        let s = await setup()
        defer { try? FileManager.default.removeItem(at: s.directory) }
        await s.server.put(norwayURL, Data(repeating: 8, count: 2500), sizeKnown: false)
        let plan = try await s.manager.plan(for: selection())
        #expect(plan.items[0].size == nil && plan.items[1].size == 3000)
        #expect(plan.hasUnknownSizes && plan.bytesToDownload == 3000, "a lower bound")
        _ = try await s.manager.fetch(plan)
        #expect(s.manager.cache.status(ofRegionID: "norway").record?.size == 2500)
    }

    @Test("Without an ETag an interrupted download starts again")
    func noETagNoResume() async throws {
        let s = await setup()
        defer { try? FileManager.default.removeItem(at: s.directory) }
        await s.server.put(norwayURL, Data(repeating: 6, count: 4000), etag: nil)
        let one = RegionSelection(regions: [region("norway", norwayURL)], coveredShare: 1)
        let plan = try await s.manager.plan(for: one)
        await s.server.cutNextDownload(after: 1500)
        await #expect(throws: (any Error).self) { try await s.manager.fetch(plan) }
        let next = try await s.manager.plan(for: one)
        #expect(next.items[0].alreadyDownloaded == 0)
        _ = try await s.manager.fetch(next)
        #expect(await s.server.requests(containing: "GET").last == "GET \(norwayURL) from 0")
        #expect(s.manager.cache.status(ofRegionID: "norway").record?.size == 4000)
    }

    @Test("A fetch is refused while another process holds the cache's download lock, and nothing is downloaded")
    func otherProcess() async throws {
        let s = await setup()
        defer { try? FileManager.default.removeItem(at: s.directory) }
        let plan = try await s.manager.plan(for: selection())
        let other = try SourceCache(directory: s.directory).lockDownloads()
        await #expect(throws: SourceError.cacheBusy) { try await s.manager.fetch(plan) }
        #expect(await s.server.requests(containing: "GET").isEmpty)
        other.release()
        _ = try await s.manager.fetch(plan)
        #expect(await s.server.requests(containing: "GET").count == 2)
    }

    @Test("A region that is being downloaded cannot be downloaded again at the same time")
    func concurrent() async throws {
        let gate = Gate()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-manager-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = SourceManager(cache: SourceCache(directory: directory, availableCapacity: { _ in nil }), downloader: GatedDownloader(gate: gate))
        let one = RegionSelection(regions: [region("norway", norwayURL)], coveredShare: 1)
        let plan = try await manager.plan(for: one)
        let first = Task { try await manager.fetch(plan) }
        await gate.waitUntilEntered()
        await #expect(throws: SourceError.alreadyDownloading(region: "norway")) { try await manager.fetch(plan) }
        await gate.release()
        _ = try await first.value
        // Once the first has finished the region can be fetched again (it is current, so nothing is downloaded).
        _ = try await manager.fetch(try await manager.plan(for: one))
        #expect(manager.cache.status(ofRegionID: "norway").record?.size == 1000)
    }

    @Test("A server without an ETag: the same size and modification date mean the same file")
    func noETag() async throws {
        let s = await setup()
        defer { try? FileManager.default.removeItem(at: s.directory) }
        await s.server.put(norwayURL, Data(repeating: 3, count: 1000), etag: nil, lastModified: "Tue, 02 Jan 2026 00:00:00 GMT")
        let one = RegionSelection(regions: [region("norway", norwayURL)], coveredShare: 1)
        _ = try await s.manager.fetch(try await s.manager.plan(for: one))
        s.clock.advance(days: 31)
        #expect(try await s.manager.plan(for: one).items.map(\.action) == [.useCached])
        s.clock.advance(days: 31)
        await s.server.put(norwayURL, Data(repeating: 4, count: 1000), etag: nil, lastModified: "Wed, 03 Jan 2026 00:00:00 GMT")
        #expect(try await s.manager.plan(for: one).items.map(\.action) == [.update])
    }
}

/// Lets a test hold a download until it says go.
private actor Gate {
    private var entered = false
    private var waiting: CheckedContinuation<Void, Never>?
    private var released = false

    func hold() async {
        entered = true
        if released { return }
        await withCheckedContinuation { waiting = $0 }
    }

    func waitUntilEntered() async { while !entered { await Task.yield() } }

    func release() {
        released = true
        waiting?.resume()
        waiting = nil
    }
}

/// A downloader whose download waits at a gate.
private struct GatedDownloader: Downloader {
    let gate: Gate
    func metadata(of url: URL, ifNoneMatch etag: String?) async throws -> RemoteMetadata {
        .info(RemoteFileInfo(size: 1000, etag: "\"g\""))
    }
    func download(
        from url: URL, to file: URL, resumeFrom offset: Int64, ifRange etag: String?, progress: @Sendable (Int64) -> Void
    ) async throws -> RemoteFileInfo {
        await gate.hold()
        try Data(repeating: 2, count: 1000).write(to: file)
        return RemoteFileInfo(size: 1000, etag: "\"g\"")
    }
}

/// Collects progress reports from a download.
private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: (Int64, Int64?)] = [:]
    func add(_ id: String, _ bytes: Int64, _ total: Int64?) { lock.lock(); entries[id] = (bytes, total); lock.unlock() }
    func last(_ id: String) -> (Int64, Int64)? {
        lock.lock(); defer { lock.unlock() }
        return entries[id].flatMap { entry in entry.1.map { (entry.0, $0) } }
    }
}
