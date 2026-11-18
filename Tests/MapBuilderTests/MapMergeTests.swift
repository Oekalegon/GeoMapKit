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
        #expect(report.warnings.contains { $0.contains("more than one map") } && report.nextSteps.contains { $0.contains("fill-sea") })
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
        // The block that was replaced has a file of its own name, and the file it replaced is gone: the manifest is what switches.
        let replacedBlock = try #require(merged.blocks.first { $0.x == 130 })
        #expect(replacedBlock.file != "blocks/8-130-90.gmk" && FileManager.default.fileExists(atPath: base.appendingPathComponent(replacedBlock.file).path))
        #expect(!FileManager.default.fileExists(atPath: base.appendingPathComponent("blocks/8-130-90.gmk").path))
    }

    @Test("The merged files hold the bytes of the blocks that were kept, whatever the order of the maps")
    func contents() async throws {
        let r = root()
        defer { try? FileManager.default.removeItem(at: r) }
        let a = try map(r, "a", blocks: [(10, 5, 64), (11, 5, 32)])
        let b = try map(r, "b", blocks: [(11, 5, 96), (12, 5, 16)])
        // The map that is added to is the second one in the list.
        _ = try await MapBuilder.mergeMaps(MapMergeRequest(inputs: [b, a], output: a))
        let merged = try read(a)
        for block in merged.blocks {
            let expected = Data(repeating: UInt8(block.x & 0xff), count: Int(block.bytes))
            #expect(try Data(contentsOf: a.appendingPathComponent(block.file)) == expected, "block \(block.x)")
        }
        #expect(merged.blocks.map(\.bytes) == [64, 96, 16])
    }

    @Test("With three maps, a tie goes to the map that is added to, and then to the earlier one")
    func ties() async throws {
        let r = root()
        defer { try? FileManager.default.removeItem(at: r) }
        let a = try map(r, "a", blocks: [(1, 1, 50)])
        let b = try map(r, "b", blocks: [(1, 1, 50)])
        let c = try map(r, "c", blocks: [(1, 1, 50)])
        let first = try await MapBuilder.mergeMaps(MapMergeRequest(inputs: [a, b, c], output: r.appendingPathComponent("out")))
        #expect(first.overlaps.first?.kept == "a" && first.overlaps.first?.dropped == ["b", "c"])
        let inPlace = try await MapBuilder.mergeMaps(MapMergeRequest(inputs: [a, b, c], output: c))
        #expect(inPlace.overlaps.first?.kept == "c" && inPlace.written == 0 && inPlace.replaced == 0)
    }

    @Test("The levels of a map that is added to stay, and a new map has none")
    func levels() async throws {
        let r = root()
        defer { try? FileManager.default.removeItem(at: r) }
        let a = try map(r, "a", blocks: [(1, 1, 50)])
        var manifest = try read(a)
        manifest.levels = [StoreManifest.Level(topZoom: 8, blockZoom: 6, classes: [1], blocks: [
            StoreManifest.LevelBlock(x: 0, y: 0, file: "levels/8-0-0.gmk", bytes: 10, builtAt: Date(timeIntervalSince1970: 1_800_000_000),
                derivedFrom: [StoreManifest.LevelBlock.Origin(x: 1, y: 1, bytes: 50)])])]
        try manifest.jsonData().write(to: a.appendingPathComponent("manifest.json"))
        let b = try map(r, "b", blocks: [(2, 1, 60)])
        let fresh = try await MapBuilder.mergeMaps(MapMergeRequest(inputs: [a, b], output: r.appendingPathComponent("new")))
        let freshLevels = try read(r.appendingPathComponent("new")).levels
        #expect(!fresh.hasLevels && freshLevels.isEmpty)
        let added = try await MapBuilder.mergeMaps(MapMergeRequest(inputs: [a, b], output: a))
        let keptLevels = try read(a).levels
        #expect(added.hasLevels && keptLevels.first?.blocks.count == 1)
    }

    @Test("A merge that stops in the middle leaves no folder, and the maps are as they were")
    func failedCopy() async throws {
        let r = root()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: r.appendingPathComponent("b/blocks/8-2-1.gmk").path)
            try? FileManager.default.removeItem(at: r)
        }
        let a = try map(r, "a", blocks: [(1, 1, 10)])
        let b = try map(r, "b", blocks: [(2, 1, 10)])
        // The block has its size, so the check before the copy passes; the copy cannot read it.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: b.appendingPathComponent("blocks/8-2-1.gmk").path)
        let out = r.appendingPathComponent("out")
        await #expect(throws: MapBuilderError.self) { try await MapBuilder.mergeMaps(MapMergeRequest(inputs: [a, b], output: out)) }
        #expect(!FileManager.default.fileExists(atPath: out.path))
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
