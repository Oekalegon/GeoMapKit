import FeatureStore
import Foundation
import GeoCore
import Regions
import Testing
import ToolSupport
@testable import ToolCommands

/// The commands that find, fetch and use the source files of an area, with a catalog and a network in memory.
@Suite("Source commands")
struct SourcesCommandTests {
    private let tinyURL = URL(string: "https://download.example.org/europe/tiny-latest.osm.pbf")!
    private let otherURL = URL(string: "https://download.example.org/europe/other-latest.osm.pbf")!

    private struct FixedCatalog: RegionCatalog {
        let regions: [SourceRegion]
        func index() async throws -> RegionIndex { try RegionIndex(regions: regions) }
    }

    /// A network with files in memory, that counts what was downloaded.
    private actor Network: Downloader {
        var files: [URL: Data] = [:]
        private(set) var downloads: [URL] = []
        func put(_ url: URL, _ data: Data) { files[url] = data }

        func metadata(of url: URL, ifNoneMatch etag: String?) async throws -> RemoteMetadata {
            guard let data = files[url] else { throw URLError(.fileDoesNotExist) }
            return .info(RemoteFileInfo(size: Int64(data.count), etag: "\"e\""))
        }

        func download(
            from url: URL, to file: URL, resumeFrom offset: Int64, ifRange etag: String?, progress: @Sendable (Int64) -> Void
        ) async throws -> RemoteFileInfo {
            guard let data = files[url] else { throw URLError(.fileDoesNotExist) }
            downloads.append(url)
            try data.write(to: file)
            progress(Int64(data.count))
            return RemoteFileInfo(size: Int64(data.count), etag: "\"e\"")
        }
    }

    /// A network on which every file has changed since it was downloaded.
    private struct ReplacingNetwork: Downloader {
        let base: Network
        func metadata(of url: URL, ifNoneMatch etag: String?) async throws -> RemoteMetadata {
            .info(RemoteFileInfo(size: 123_456, etag: "\"new\""))
        }
        func download(
            from url: URL, to file: URL, resumeFrom offset: Int64, ifRange etag: String?, progress: @Sendable (Int64) -> Void
        ) async throws -> RemoteFileInfo { try await base.download(from: url, to: file, resumeFrom: offset, ifRange: etag, progress: progress) }
    }

    private struct OfflineNetwork: Downloader {
        func metadata(of url: URL, ifNoneMatch etag: String?) async throws -> RemoteMetadata { throw URLError(.notConnectedToInternet) }
        func download(
            from url: URL, to file: URL, resumeFrom offset: Int64, ifRange etag: String?, progress: @Sendable (Int64) -> Void
        ) async throws -> RemoteFileInfo { throw URLError(.notConnectedToInternet) }
    }

    private func region(_ id: String, _ url: URL, west: Double, east: Double) -> SourceRegion {
        let ring = [
            Coordinate(latitude: 46, longitude: west), Coordinate(latitude: 46, longitude: east),
            Coordinate(latitude: 49, longitude: east), Coordinate(latitude: 49, longitude: west),
        ]
        return SourceRegion(id: id, name: id.capitalized, parentID: nil, pbfURL: url, outline: [RegionPolygon(outer: ring)])
    }

    private struct Setup {
        let catalog: FixedCatalog
        let network: Network
        let cache: URL
    }

    private func setup() async throws -> Setup {
        let network = Network()
        await network.put(tinyURL, try TinyPBF.make())
        await network.put(otherURL, Data(repeating: 0, count: 5_000))
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-tools-\(UUID().uuidString)")
        let regions = [region("tiny", tinyURL, west: 8, east: 10.5), region("other", otherURL, west: 11, east: 12)]
        return Setup(catalog: FixedCatalog(regions: regions), network: network, cache: cache)
    }

    private let area = BoundingBox(south: 47, west: 9, north: 48, east: 10)

    @Test("sources lists the files an area needs with their sizes, and downloads nothing")
    func sources() async throws {
        let s = try await setup()
        defer { try? FileManager.default.removeItem(at: s.cache) }
        let report = try await ToolRunner.sources(area: area, cacheDirectory: s.cache, catalog: s.catalog, downloader: s.network)
        #expect(report.plan.items.map(\.region.id) == ["tiny"])
        #expect(report.plan.items.map(\.action) == [.download] && report.plan.items[0].size != nil)
        #expect(!report.downloaded && report.cacheDirectory == s.cache)
        #expect(await s.network.downloads.isEmpty)
        let text = ReportFormatter.text(for: report)
        #expect(text.contains("to download") && text.contains("Nothing was downloaded") && text.contains("--yes"))
        #expect(text.contains("Tiny") && text.contains("tiny"))
    }

    @Test("fetch downloads only when it is told to, and a second run finds everything in the cache")
    func fetch() async throws {
        let s = try await setup()
        defer { try? FileManager.default.removeItem(at: s.cache) }
        let asked = try await ToolRunner.fetch(
            area: area, cacheDirectory: s.cache, catalog: s.catalog, downloader: s.network, confirmed: false)
        #expect(!asked.downloaded && asked.plan.needsDownload && asked.downloadTime == nil)
        #expect(await s.network.downloads.isEmpty)

        let done = try await ToolRunner.fetch(
            area: area, cacheDirectory: s.cache, catalog: s.catalog, downloader: s.network, confirmed: true)
        #expect(done.downloaded && done.downloadTime != nil)
        #expect(await s.network.downloads == [tinyURL])
        #expect(ReportFormatter.text(for: done).contains("Downloaded in"))

        let again = try await ToolRunner.fetch(
            area: area, cacheDirectory: s.cache, catalog: s.catalog, downloader: s.network, confirmed: true)
        #expect(!again.downloaded && !again.plan.needsDownload)
        #expect(ReportFormatter.text(for: again).contains("Everything is in the cache"))
        #expect(await s.network.downloads.count == 1)
    }

    @Test("cachedSources refuses files that are not cached and says to run fetch; after a fetch it gives files and records")
    func cachedSources() async throws {
        let s = try await setup()
        defer { try? FileManager.default.removeItem(at: s.cache) }
        do {
            _ = try await ToolRunner.cachedSources(area: area, cacheDirectory: s.cache, catalog: s.catalog, downloader: s.network)
            Issue.record("it did not refuse")
        } catch let error as ToolError {
            #expect("\(error)".contains("Tiny (tiny)") && "\(error)".contains("geomapkit fetch"))
        }
        #expect(await s.network.downloads.isEmpty, "it never downloads")

        _ = try await ToolRunner.fetch(area: area, cacheDirectory: s.cache, catalog: s.catalog, downloader: s.network, confirmed: true)
        let cached = try await ToolRunner.cachedSources(area: area, cacheDirectory: s.cache, catalog: s.catalog, downloader: s.network)
        #expect(cached.files.map(\.lastPathComponent) == ["tiny.osm.pbf"] && cached.records.map(\.regionID) == ["tiny"])
        #expect(cached.coveredShare > 0.9)
    }

    @Test("A file the server has replaced is refused for a build unless stale files are allowed, and then a warning says so")
    func staleSources() async throws {
        let s = try await setup()
        defer { try? FileManager.default.removeItem(at: s.cache) }
        _ = try await ToolRunner.fetch(area: area, cacheDirectory: s.cache, catalog: s.catalog, downloader: s.network, confirmed: true)
        // The server now has another version of the file, and the cached one is older than 30 days.
        let later = ReplacingNetwork(base: s.network)
        let old = SourceCache(directory: s.cache)
        var record = try #require(old.status(ofRegionID: "tiny").record)
        record.checkedAt = Date().addingTimeInterval(-40 * 86_400)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(to: s.cache.appendingPathComponent("tiny.osm.pbf.json"))
        do {
            _ = try await ToolRunner.cachedSources(area: area, cacheDirectory: s.cache, catalog: s.catalog, downloader: later)
            Issue.record("it did not refuse")
        } catch let error as ToolError {
            #expect("\(error)".contains("out of date") && "\(error)".contains("--allow-stale"))
        }
        let allowed = try await ToolRunner.cachedSources(
            area: area, cacheDirectory: s.cache, catalog: s.catalog, downloader: later, allowStale: true)
        #expect(allowed.files.count == 1 && allowed.warnings.count == 1 && allowed.warnings[0].contains("older than the file on the server"))
    }

    @Test("A file that cannot be checked is used with a warning")
    func unchecked() async throws {
        let s = try await setup()
        defer { try? FileManager.default.removeItem(at: s.cache) }
        _ = try await ToolRunner.fetch(area: area, cacheDirectory: s.cache, catalog: s.catalog, downloader: s.network, confirmed: true)
        let old = SourceCache(directory: s.cache)
        var record = try #require(old.status(ofRegionID: "tiny").record)
        record.checkedAt = Date().addingTimeInterval(-40 * 86_400)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(to: s.cache.appendingPathComponent("tiny.osm.pbf.json"))
        let cached = try await ToolRunner.cachedSources(area: area, cacheDirectory: s.cache, catalog: s.catalog, downloader: OfflineNetwork())
        #expect(cached.warnings.count == 1 && cached.warnings[0].contains("could not be checked"))
    }

    @Test("A build from the cache makes a store and records its sources next to it")
    func buildFromCache() async throws {
        let s = try await setup()
        defer { try? FileManager.default.removeItem(at: s.cache) }
        _ = try await ToolRunner.fetch(area: area, cacheDirectory: s.cache, catalog: s.catalog, downloader: s.network, confirmed: true)
        let cached = try await ToolRunner.cachedSources(area: area, cacheDirectory: s.cache, catalog: s.catalog, downloader: s.network)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-\(UUID().uuidString).gmk")
        defer {
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: BuildSources.url(forStore: output))
        }
        let report = try ToolRunner.build(urls: cached.files, area: area, output: output, profile: .full)
        let record = BuildSources(builtAt: Date(timeIntervalSince1970: 1_800_000_000), area: report.cut.area, sources: cached.records)
        try record.write(besides: output)
        #expect(BuildSources.url(forStore: output).lastPathComponent == output.lastPathComponent + ".sources.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(BuildSources.self, from: Data(contentsOf: BuildSources.url(forStore: output)))
        #expect(back == record && back.sources.map(\.regionID) == ["tiny"] && back.sources[0].etag == "\"e\"")
    }

    @Test("The files of the blocks of regions are listed with the number of blocks, and a fetch for them downloads only when confirmed")
    func byRegion() async throws {
        let s = try await setup()
        defer { try? FileManager.default.removeItem(at: s.cache) }
        let report = try await ToolRunner.sources(regions: ["tiny"], cacheDirectory: s.cache, catalog: s.catalog, downloader: s.network)
        // The blocks at the east edge of the tiny region reach into the next region with their margin, so both files are needed.
        #expect(Set(report.plan.items.map(\.region.id)) == ["tiny", "other"] && report.blockCount != nil && report.blockCount! > 1)
        #expect(report.plan.items.first?.region.id == "tiny", "the file that most blocks need comes first")
        let text = ReportFormatter.text(for: report)
        #expect(text.contains("Blocks: \(report.blockCount!)") && !text.contains("outlines of these regions cover"), "no coverage line for regions")
        #expect(await s.network.downloads.isEmpty)
        let asked = try await ToolRunner.fetch(regions: ["tiny"], cacheDirectory: s.cache, catalog: s.catalog, downloader: s.network, confirmed: false)
        #expect(!asked.downloaded && asked.plan.needsDownload)
        let done = try await ToolRunner.fetch(regions: ["tiny"], cacheDirectory: s.cache, catalog: s.catalog, downloader: s.network, confirmed: true)
        let downloaded = await s.network.downloads
        #expect(done.downloaded && Set(downloaded) == [tinyURL, otherURL])
        await #expect(throws: ToolError.self) {
            try await ToolRunner.sources(regions: ["narnia"], cacheDirectory: s.cache, catalog: s.catalog, downloader: s.network)
        }
    }

    @Test("An area that no region covers, and an invalid area, are refused")
    func nothingCovers() async throws {
        let s = try await setup()
        defer { try? FileManager.default.removeItem(at: s.cache) }
        await #expect(throws: ToolError.self) {
            try await ToolRunner.sources(area: BoundingBox(south: -10, west: 100, north: -9, east: 101), cacheDirectory: s.cache, catalog: s.catalog, downloader: s.network)
        }
        await #expect(throws: ToolError.self) {
            try await ToolRunner.sources(area: BoundingBox(south: 5, west: 1, north: 4, east: 2), cacheDirectory: s.cache, catalog: s.catalog, downloader: s.network)
        }
    }

    @Test("The report names a file that could not be checked, and an update")
    func reportStates() throws {
        let tiny = region("tiny", tinyURL, west: 8, east: 10)
        let plan = DownloadPlan(
            items: [
                PlanItem(region: tiny, action: .useCached, size: 100, checkFailure: "offline"),
                PlanItem(region: region("other", otherURL, west: 10, east: 12), action: .update, size: nil, alreadyDownloaded: 2_048),
            ], coveredShare: 0.5)
        let text = ReportFormatter.text(for: SourcesReport(area: area, cacheDirectory: URL(fileURLWithPath: "/cache"), plan: plan))
        #expect(text.contains("could not be checked: offline") && text.contains("newer on the server") && text.contains("size unknown"))
        #expect(text.contains("2.0 KB already there") || text.contains("already there"))
        #expect(text.contains("at least") && text.contains("50 %"))
    }
}
