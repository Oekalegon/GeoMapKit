import FeatureStore
import Foundation
import Testing

@testable import MapBuilder

@Suite("merge-maps")
struct MapMergeTests {
    /// A map of fake blocks: each block file holds as many bytes as it is given, and the manifest says so. Nothing opens the blocks.
    private func map(
        _ root: URL, _ name: String, blocks: [(x: Int, y: Int, bytes: Int)], profile: String = "full", classifier: Int = 3,
        attribution: String = "© OpenStreetMap contributors"
    ) throws -> URL {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("blocks"), withIntermediateDirectories: true)
        var entries: [StoreManifest.Block] = []
        for block in blocks {
            let file = "blocks/8-\(block.x)-\(block.y).gmk"
            try Data(repeating: UInt8(block.x & 0xff), count: block.bytes).write(to: folder.appendingPathComponent(file))
            entries.append(StoreManifest.Block(x: block.x, y: block.y, file: file, bytes: Int64(block.bytes), builtAt: Date(timeIntervalSince1970: 1_800_000_000)))
        }
        let manifest = StoreManifest(
            formatVersion: 1, classifierVersion: classifier, storageZoom: 13, blockZoom: 8, bands: [.overview, .mid, .detail], profile: profile,
            attribution: attribution, blocks: entries)
        try manifest.jsonData().write(to: folder.appendingPathComponent("manifest.json"))
        return folder
    }

    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-merge-\(UUID().uuidString)", isDirectory: true)
    }

    private func read(_ folder: URL) throws -> StoreManifest {
        try StoreManifest(json: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
    }

    @Test("Two maps with different tiles make a new map with all blocks, copied as they are")
    func newMap() async throws {
        let r = root()
        defer { try? FileManager.default.removeItem(at: r) }
        let a = try map(r, "ch", blocks: [(130, 90, 100), (131, 90, 200)])
        let b = try map(r, "es", blocks: [(120, 95, 300)])
        let out = r.appendingPathComponent("out")
        let report = try await MapBuilder.mergeMaps(MapMergeRequest(inputs: [a, b], output: out))
        #expect(report.blocks == 3 && report.written == 3 && report.overlaps.isEmpty && !report.hasLevels)
        let merged = try read(out)
        #expect(merged.blocks.map { "\($0.x)/\($0.y)" } == ["130/90", "131/90", "120/95"], "ordered by row and column")
        for block in merged.blocks {
            let size = try FileManager.default.attributesOfItem(atPath: out.appendingPathComponent(block.file).path)[.size] as? Int
            #expect(Int64(size ?? 0) == block.bytes)
        }
    }

    @Test("A tile that two maps have keeps the larger block, and the report says which")
    func overlap() async throws {
        let r = root()
        defer { try? FileManager.default.removeItem(at: r) }
        let a = try map(r, "ch", blocks: [(130, 90, 100)])
        let b = try map(r, "fr", blocks: [(130, 90, 500)])
        let report = try await MapBuilder.mergeMaps(MapMergeRequest(inputs: [a, b], output: r.appendingPathComponent("out")))
        let overlap = try #require(report.overlaps.first)
        #expect(report.blocks == 1 && overlap.kept == "fr" && overlap.dropped == ["ch"] && overlap.keptBytes == 500 && overlap.droppedBytes == [100])
        #expect(try read(r.appendingPathComponent("out")).blocks.first?.bytes == 500)
        #expect(report.warnings.contains { $0.contains("more than one map") })
    }

    @Test("Adding to a map keeps its blocks and writes only the others; a larger block replaces a smaller, and the old manifest is kept")
    func inPlace() async throws {
        let r = root()
        defer { try? FileManager.default.removeItem(at: r) }
        let base = try map(r, "europe", blocks: [(130, 90, 100), (131, 90, 200)])
        let added = try map(r, "ch", blocks: [(130, 90, 400), (131, 90, 50), (132, 90, 70)])
        let baseFile = base.appendingPathComponent("blocks/8-131-90.gmk")
        let before = try Data(contentsOf: baseFile)
        let report = try await MapBuilder.mergeMaps(MapMergeRequest(inputs: [base, added], output: base))
        #expect(report.blocks == 3 && report.written == 2 && report.replaced == 1 && report.overlaps.count == 2)
        #expect(try Data(contentsOf: baseFile) == before, "a larger block of the map itself stays")
        let merged = try read(base)
        #expect(merged.blocks.first { $0.x == 130 }?.bytes == 400 && merged.blocks.first { $0.x == 131 }?.bytes == 200)
        #expect(merged.blocks.count == 3)
        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("manifest.before-merge.json").path))
        let old = try StoreManifest(json: Data(contentsOf: base.appendingPathComponent("manifest.before-merge.json")))
        #expect(old.blocks.count == 2)
    }

    @Test("Maps that do not agree on the format are refused, with the difference named")
    func incompatible() async throws {
        let r = root()
        defer { try? FileManager.default.removeItem(at: r) }
        let a = try map(r, "a", blocks: [(1, 1, 10)])
        let watch = try map(r, "w", blocks: [(2, 1, 10)], profile: "watch")
        let old = try map(r, "o", blocks: [(3, 1, 10)], classifier: 2)
        for other in [watch, old] {
            do {
                _ = try await MapBuilder.mergeMaps(MapMergeRequest(inputs: [a, other], output: r.appendingPathComponent("out")))
                Issue.record("the merge should refuse \(other.lastPathComponent)")
            } catch let error as MapBuilderError {
                #expect("\(error)".contains(other.lastPathComponent) && ("\(error)".contains("profile") || "\(error)".contains("rule table")))
            }
        }
        #expect(!FileManager.default.fileExists(atPath: r.appendingPathComponent("out").path), "nothing was written")
    }

    @Test("A block that is missing, a folder without a manifest, one map, the same map twice and a used output are refused")
    func refused() async throws {
        let r = root()
        defer { try? FileManager.default.removeItem(at: r) }
        let a = try map(r, "a", blocks: [(1, 1, 10)])
        let b = try map(r, "b", blocks: [(2, 1, 10)])
        try FileManager.default.removeItem(at: b.appendingPathComponent("blocks/8-2-1.gmk"))
        let out = r.appendingPathComponent("out")
        await #expect(throws: MapBuilderError.self) { try await MapBuilder.mergeMaps(MapMergeRequest(inputs: [a, b], output: out)) }
        let empty = r.appendingPathComponent("nothing")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        await #expect(throws: MapBuilderError.self) { try await MapBuilder.mergeMaps(MapMergeRequest(inputs: [a, empty], output: out)) }
        await #expect(throws: MapBuilderError.self) { try await MapBuilder.mergeMaps(MapMergeRequest(inputs: [a], output: out)) }
        await #expect(throws: MapBuilderError.self) { try await MapBuilder.mergeMaps(MapMergeRequest(inputs: [a, a], output: out)) }
        let c = try map(r, "c", blocks: [(3, 1, 10)])
        await #expect(throws: MapBuilderError.self) { try await MapBuilder.mergeMaps(MapMergeRequest(inputs: [a, c], output: b)) }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    @Test("The credits of the maps are kept, once each")
    func credits() async throws {
        let r = root()
        defer { try? FileManager.default.removeItem(at: r) }
        let a = try map(r, "a", blocks: [(1, 1, 10)])
        let b = try map(r, "b", blocks: [(2, 1, 10)], attribution: "© Other")
        let same = try map(r, "c", blocks: [(3, 1, 10)])
        _ = try await MapBuilder.mergeMaps(MapMergeRequest(inputs: [a, b, same], output: r.appendingPathComponent("out")))
        #expect(try read(r.appendingPathComponent("out")).attribution == "© OpenStreetMap contributors | © Other")
    }
}
