import FeatureStore
import FeatureStoreBuilder
import Foundation
import GeoCore
import MapBuilder
import Regions
import Testing
import ToolSupport
@testable import ToolCommands

/// `compare`: the features that differ between two stores in the cells both hold.
@Suite("compare")
struct StoreComparisonTests {
    private let area = BoundingBox(south: 47, west: 9, north: 48, east: 10)

    private func store(profile: BuildProfile = .full, extraWay: Bool = false, in folder: URL, name: String) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let input = folder.appendingPathComponent("\(name).osm.pbf")
        try (extraWay ? TinyPBF.makeWithExtraWay() : TinyPBF.make()).write(to: input)
        let output = folder.appendingPathComponent("\(name).gmk")
        _ = try ToolRunner.build(url: input, area: area, output: output, profile: profile)
        return output
    }

    private func folder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-compare-\(UUID().uuidString)") }

    @Test("A store is the same as itself, and as another build of the same data")
    func same() throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = try store(in: folder, name: "a"), b = try store(in: folder, name: "b")
        let result = try ToolRunner.compareStores(a, b)
        #expect(result.cellsCompared > 0 && result.cellsIdentical == result.cellsCompared)
        #expect(result.differenceCount == 0 && result.cellsOnlyInFirst == 0 && result.cellsSkippedNearEdge == 0)
        let text = ReportFormatter.text(for: result)
        #expect(text.contains("identical: \(result.cellsCompared)") && text.contains("Features that differ: 0"))
    }

    @Test("A feature that only one store has is named, with the store that has it")
    func different() throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let plain = try store(in: folder, name: "plain"), more = try store(extraWay: true, in: folder, name: "more")
        let result = try ToolRunner.compareStores(plain, more, limit: 1)
        #expect(result.differenceCount > 0 && result.cellsIdentical < result.cellsCompared)
        #expect(result.differences.count == 1)
        #expect(result.differences.allSatisfy { $0.onlyIn == "second" }, "the second store has the extra way")
        let text = ReportFormatter.text(for: result)
        #expect(text.contains("only in the second store") && text.contains("12"))
        if result.differenceCount > 1 { #expect(text.contains("and \(result.differenceCount - 1) more")) }
        // The other way round, the first store has it.
        #expect(try ToolRunner.compareStores(more, plain).differences.allSatisfy { $0.onlyIn == "first" })
    }

    @Test("A file can be compared with a manifest of blocks")
    func withManifest() async throws {
        let root = folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try store(in: root, name: "one")
        let cache = SourceCache(directory: root.appendingPathComponent("cache"))
        let data = try TinyPBF.make()
        let part = try cache.preparePart(regionID: "tiny", etag: "\"e\"", keepBytes: false)
        try data.write(to: part)
        try cache.install(
            regionID: "tiny", from: URL(string: "https://download.example.org/tiny.osm.pbf")!,
            info: RemoteFileInfo(size: Int64(data.count), etag: "\"e\""))
        struct Catalog: RegionCatalog {
            func index() async throws -> RegionIndex {
                let ring = [Coordinate(latitude: 46, longitude: 8), Coordinate(latitude: 46, longitude: 10.5), Coordinate(latitude: 49, longitude: 10.5), Coordinate(latitude: 49, longitude: 8)]
                return try RegionIndex(regions: [SourceRegion(
                    id: "tiny", name: "Tiny", parentID: nil, pbfURL: URL(string: "https://download.example.org/tiny.osm.pbf")!,
                    outline: [RegionPolygon(outer: ring)])])
            }
        }
        let report = try await MapBuilder.buildRegion(
            BlockRequest(area: .box(area), output: root.appendingPathComponent("blocks"), cacheDirectory: root.appendingPathComponent("cache")),
            catalog: Catalog())
        let result = try ToolRunner.compareStores(file, report.manifestURL)
        #expect(result.cellsCompared > 0)
        // The tiny map has one block's worth of data, in a few cells; what both hold must be the same.
        #expect(result.differenceCount == 0, "\(ReportFormatter.text(for: result))")
    }

    @Test("Cells near the edge of the first store can be left out, and are counted")
    func inner() throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = try store(in: folder, name: "a"), b = try store(in: folder, name: "b")
        let all = try ToolRunner.compareStores(a, b)
        let inner = try ToolRunner.compareStores(a, b, inner: 1)
        #expect(inner.cellsSkippedNearEdge > 0)
        #expect(inner.cellsCompared + inner.cellsSkippedNearEdge + inner.cellsOnlyInFirst == all.cellsCompared + all.cellsOnlyInFirst)
        #expect(ReportFormatter.text(for: inner).contains("left out near its edge: \(inner.cellsSkippedNearEdge)"))
        // Everything left out: nothing compared.
        #expect(try ToolRunner.compareStores(a, b, inner: 1_000).cellsCompared == 0)
    }

    @Test("A store that cannot be opened is a ToolError")
    func cannotOpen() throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = try store(in: folder, name: "a")
        #expect(throws: ToolError.self) { try ToolRunner.compareStores(a, folder.appendingPathComponent("missing.gmk")) }
        #expect(throws: ToolError.self) { try ToolRunner.compareStores(a, folder.appendingPathComponent("manifest.json")) }
    }
}
