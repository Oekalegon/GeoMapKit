import FeatureStore
import FeatureStoreBuilder
import Foundation
import GeoCore
import Regions
import Testing
import ToolSupport
@testable import ToolCommands

/// `build-region`: blocks and a manifest from source files in the cache.
@Suite("build-region")
struct BuildRegionTests {
    private let tinyURL = URL(string: "https://download.example.org/europe/tiny-latest.osm.pbf")!

    private struct FixedCatalog: RegionCatalog {
        let regions: [SourceRegion]
        func index() async throws -> RegionIndex { try RegionIndex(regions: regions) }
    }

    private func rectangle(_ id: String, west: Double, south: Double, east: Double, north: Double) -> SourceRegion {
        let ring = [
            Coordinate(latitude: south, longitude: west), Coordinate(latitude: south, longitude: east),
            Coordinate(latitude: north, longitude: east), Coordinate(latitude: north, longitude: west),
        ]
        return SourceRegion(
            id: id, name: id.capitalized, parentID: nil, pbfURL: URL(string: "https://download.example.org/\(id).osm.pbf")!,
            outline: [RegionPolygon(outer: ring)])
    }

    private struct Setup {
        let catalog: FixedCatalog
        let cache: URL
        let output: URL
        let cacheStore: SourceCache
    }

    private func setup(install: Bool = true, etag: String = "\"e1\"") throws -> Setup {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-region-\(UUID().uuidString)")
        let cache = SourceCache(directory: root.appendingPathComponent("cache"))
        let region = rectangle("tiny", west: 8, south: 46, east: 10.5, north: 49)
        if install { try put(cache, etag: etag) }
        return Setup(catalog: FixedCatalog(regions: [region]), cache: root.appendingPathComponent("cache"), output: root.appendingPathComponent("out"), cacheStore: cache)
    }

    /// Puts the tiny PBF file into the cache the way a download does.
    private func put(_ cache: SourceCache, etag: String) throws {
        let data = try TinyPBF.make()
        let part = try cache.preparePart(regionID: "tiny", etag: etag, keepBytes: false)
        try data.write(to: part)
        try cache.install(regionID: "tiny", from: tinyURL, info: RemoteFileInfo(size: Int64(data.count), etag: etag, lastModified: "Mon"))
    }

    private let area = BoundingBox(south: 47, west: 9, north: 48, east: 10)

    private func request(_ s: Setup, area: BlockRequest.Area? = nil, jobs: Int = 1, profile: BuildProfile = .full, output: URL? = nil) -> BlockRequest {
        BlockRequest(area: area ?? .box(self.area), output: output ?? s.output, blockZoom: 8, jobs: jobs, margin: 0.1, profile: profile, cacheDirectory: s.cache)
    }

    private func built(_ report: BlockRunReport) -> [BlockOutcome] {
        report.outcomes.filter { if case .built = $0.status { return true } else { return false } }
    }

    @Test("The blocks of an area are built, listed in a manifest, and can be read as one map")
    func firstRun() async throws {
        let s = try setup()
        defer { try? FileManager.default.removeItem(at: s.output.deletingLastPathComponent()) }
        var seen: [BlockOutcome] = []
        let report = try await ToolRunner.buildRegion(request(s), catalog: s.catalog) { seen.append($0) }
        #expect(report.outcomes.count >= 1 && seen.count == report.outcomes.count)
        #expect(!built(report).isEmpty)
        #expect(built(report).allSatisfy { $0.regions == ["tiny"] })

        let set = try StoreSet(manifestURL: report.manifestURL)
        #expect(set.manifest.blockZoom == 8 && set.manifest.storageZoom == 13 && set.manifest.profile == "full")
        #expect(set.manifest.classifierVersion == Int(FeatureClassifier.version))
        #expect(set.manifest.blocks.count == built(report).count)
        let source = try #require(set.manifest.blocks.first?.sources.first)
        #expect(source.regionID == "tiny" && source.etag == "\"e1\"" && source.url == tinyURL.absoluteString)
        // A cell of the tiny map is in a block, and the way of the test is in it.
        let cell = try #require(TileID.containing(Coordinate(latitude: 47.5, longitude: 9.5), zoom: 13))
        let file = try #require(try set.file(containing: cell))
        #expect(try !file.features(in: cell, band: .detail).isEmpty)
        // The files that the manifest names are there, with the sizes it records.
        for block in set.manifest.blocks {
            let size = try FileManager.default.attributesOfItem(atPath: s.output.appendingPathComponent(block.file).path)[.size] as? Int
            #expect(Int64(size ?? -1) == block.bytes)
        }
        #expect(report.outcomes.map(\.status).contains(.empty), "tiles where the source has nothing are empty and have no file")
    }

    @Test("A second run leaves blocks that are built from the same files, and a changed source file rebuilds them")
    func resume() async throws {
        let s = try setup()
        defer { try? FileManager.default.removeItem(at: s.output.deletingLastPathComponent()) }
        let first = try await ToolRunner.buildRegion(request(s), catalog: s.catalog)
        let manifest = try Data(contentsOf: first.manifestURL)
        let second = try await ToolRunner.buildRegion(request(s), catalog: s.catalog)
        #expect(built(second).isEmpty)
        #expect(second.outcomes.filter { $0.status == .upToDate }.count == built(first).count)
        #expect(try Data(contentsOf: second.manifestURL) == manifest, "nothing was written again")

        try put(s.cacheStore, etag: "\"e2\"")   // the source file was replaced
        let third = try await ToolRunner.buildRegion(request(s), catalog: s.catalog)
        #expect(built(third).count == built(first).count && !built(third).isEmpty)
        #expect(try StoreSet(manifestURL: third.manifestURL).manifest.blocks[0].sources[0].etag == "\"e2\"")
    }

    @Test("A block file that is gone or of another size is built again")
    func damagedBlock() async throws {
        let s = try setup()
        defer { try? FileManager.default.removeItem(at: s.output.deletingLastPathComponent()) }
        let first = try await ToolRunner.buildRegion(request(s), catalog: s.catalog)
        let manifest = try StoreManifest(json: Data(contentsOf: first.manifestURL))
        try Data("short".utf8).write(to: s.output.appendingPathComponent(manifest.blocks[0].file))
        let again = try await ToolRunner.buildRegion(request(s), catalog: s.catalog)
        #expect(built(again).count == 1)
        _ = try StoreSet(manifestURL: again.manifestURL).file(containing: TileID.containing(Coordinate(latitude: 47.5, longitude: 9.5), zoom: 13)!)
    }

    @Test("Source files that are not in the cache are named, with the way to get them, and nothing is built")
    func missingSources() async throws {
        let s = try setup(install: false)
        defer { try? FileManager.default.removeItem(at: s.output.deletingLastPathComponent()) }
        do {
            _ = try await ToolRunner.buildRegion(request(s), catalog: s.catalog)
            Issue.record("it did not refuse")
        } catch let error as ToolError {
            #expect("\(error)".contains("Tiny (tiny)") && "\(error)".contains("geomapkit fetch"))
        }
        #expect(!FileManager.default.fileExists(atPath: s.output.appendingPathComponent("manifest.json").path))
    }

    @Test("A manifest of another profile is not reused")
    func otherProfile() async throws {
        let s = try setup()
        defer { try? FileManager.default.removeItem(at: s.output.deletingLastPathComponent()) }
        _ = try await ToolRunner.buildRegion(request(s), catalog: s.catalog)
        let manifestURL = s.output.appendingPathComponent("manifest.json")
        #expect(FileManager.default.fileExists(atPath: manifestURL.path))
        // The Watch copy of this tiny map has nothing to store (its way is not among the Watch classes): the full manifest must not
        // be left in place as if it were the result.
        await #expect(throws: ToolError.self) { try await ToolRunner.buildRegion(request(s, profile: .watch), catalog: s.catalog) }
        #expect(!FileManager.default.fileExists(atPath: manifestURL.path), "the manifest of the other build is gone")
        // And a full run again starts from scratch.
        let again = try await ToolRunner.buildRegion(request(s), catalog: s.catalog)
        #expect(!built(again).isEmpty && again.outcomes.allSatisfy { $0.status != .upToDate })
    }

    @Test("More jobs give the same blocks")
    func jobs() async throws {
        let s = try setup()
        defer { try? FileManager.default.removeItem(at: s.output.deletingLastPathComponent()) }
        let other = s.output.deletingLastPathComponent().appendingPathComponent("out2")
        let one = try await ToolRunner.buildRegion(request(s, jobs: 1), catalog: s.catalog)
        let three = try await ToolRunner.buildRegion(request(s, jobs: 3, output: other), catalog: s.catalog)
        let a = try StoreManifest(json: Data(contentsOf: one.manifestURL)), b = try StoreManifest(json: Data(contentsOf: three.manifestURL))
        #expect(a.blocks.map { [$0.x, $0.y] } == b.blocks.map { [$0.x, $0.y] })
        for (x, y) in zip(a.blocks, b.blocks) {
            #expect(try Data(contentsOf: s.output.appendingPathComponent(x.file)) == Data(contentsOf: other.appendingPathComponent(y.file)))
        }
    }

    @Test("A region as the area gives the blocks that meet its outline; an unknown region is refused")
    func byRegion() async throws {
        let s = try setup()
        defer { try? FileManager.default.removeItem(at: s.output.deletingLastPathComponent()) }
        let report = try await ToolRunner.buildRegion(request(s, area: .regions(["tiny"])), catalog: s.catalog)
        #expect(report.outcomes.count > 4)
        #expect(report.outcomes.allSatisfy { outcome in
            let tile = TileID(zoom: 8, x: outcome.x, y: outcome.y)!
            return tile.southEast.longitude > 8 && tile.northWest.longitude < 10.5 && tile.northWest.latitude > 46 && tile.southEast.latitude < 49
        })
        await #expect(throws: ToolError.self) { try await ToolRunner.buildRegion(request(s, area: .regions(["narnia"])), catalog: s.catalog) }
        await #expect(throws: ToolError.self) { try await ToolRunner.buildRegion(request(s, area: .regions([])), catalog: s.catalog) }
    }

    @Test("Bad requests are refused")
    func badRequests() async throws {
        let s = try setup()
        defer { try? FileManager.default.removeItem(at: s.output.deletingLastPathComponent()) }
        var bad = request(s)
        bad.blockZoom = 14
        await #expect(throws: ToolError.self) { try await ToolRunner.buildRegion(bad, catalog: s.catalog) }
        bad = request(s)
        bad.margin = -1
        await #expect(throws: ToolError.self) { try await ToolRunner.buildRegion(bad, catalog: s.catalog) }
        // An area that no region covers.
        await #expect(throws: ToolError.self) {
            try await ToolRunner.buildRegion(request(s, area: .box(BoundingBox(south: -10, west: 100, north: -9, east: 101))), catalog: s.catalog)
        }
    }

    @Test("The progress lines and the summary read as text")
    func text() {
        let built = BlockOutcome(x: 134, y: 74, status: .built(bytes: 110_000_000, cells: 1_332, seconds: 84.2), regions: ["sweden", "ostlandet"])
        #expect(ReportFormatter.line(for: built, blockZoom: 8) == "block 8/134/74: built, 110.0 MB, 1,332 cells, 84.2 s (sweden, ostlandet)")
        #expect(ReportFormatter.line(for: BlockOutcome(x: 1, y: 2, status: .upToDate, regions: []), blockZoom: 8) == "block 8/1/2: up to date, left as it is")
        #expect(ReportFormatter.line(for: BlockOutcome(x: 1, y: 2, status: .empty, regions: ["x"]), blockZoom: 8).contains("nothing to store"))
        let report = BlockRunReport(
            outcomes: [built, BlockOutcome(x: 1, y: 2, status: .empty, regions: [])], manifestURL: URL(fileURLWithPath: "/out/manifest.json"),
            totalTime: .seconds(90), peakFootprint: 800_000_000, warnings: ["Sweden is old."])
        let text = ReportFormatter.text(for: report, blockZoom: 8)
        #expect(text.contains("2 in the area, 1 built (110.0 MB), 0 up to date, 1 with nothing to store"))
        #expect(text.contains("/out/manifest.json") && text.contains("warning: Sweden is old."))
    }
}
