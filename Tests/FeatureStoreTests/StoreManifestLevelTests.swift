import Foundation
import GeoCore
import Testing

@testable import FeatureStore

/// Manifest version 2: the coarse levels, and a manifest without them as before.
@Suite("Manifest levels")
struct StoreManifestLevelTests {
    private func manifest(levels: [StoreManifest.Level] = []) -> StoreManifest {
        var manifest = StoreManifest(
            formatVersion: 1, classifierVersion: 18, storageZoom: 13, blockZoom: 8, bands: [.overview, .mid, .detail], profile: "full",
            attribution: "© OpenStreetMap contributors, ODbL",
            blocks: [StoreManifest.Block(x: 140, y: 75, file: "blocks/8-140-75.gmk", bytes: 1_000, builtAt: Date(timeIntervalSince1970: 1_700_000_000))])
        manifest.levels = levels
        return manifest
    }

    private func level(_ top: Int = 8, blockZoom: Int = 8, file: String = "levels/8/8-140-75.gmk") -> StoreManifest.Level {
        StoreManifest.Level(
            topZoom: top, blockZoom: blockZoom, classes: [3, 7],
            blocks: [
                StoreManifest.LevelBlock(
                    x: 140, y: 75, file: file, bytes: 300, builtAt: Date(timeIntervalSince1970: 1_700_000_100),
                    derivedFrom: [.init(x: 140, y: 75, bytes: 1_000)])
            ])
    }

    private func read(_ manifest: StoreManifest) throws -> StoreManifest { try StoreManifest(json: try manifest.jsonData()) }

    @Test func aManifestWithLevelsIsVersion2AndRoundTrips() throws {
        let original = manifest(levels: [level(8), level(7, file: "levels/7/8-140-75.gmk")])
        let json = String(decoding: try original.jsonData(), as: UTF8.self)
        #expect(json.contains("\"version\" : 2") && json.contains("\"levels\""))
        let back = try read(original)
        #expect(back.levels == original.levels && back.blocks == original.blocks)
        #expect(back.levels[0].storageZoom == 10 && back.levels[1].storageZoom == 9)
    }

    @Test func aManifestWithoutLevelsStaysVersion1AndOldFilesStillOpen() throws {
        let json = String(decoding: try manifest().jsonData(), as: UTF8.self)
        #expect(json.contains("\"version\" : 1") && !json.contains("levels"))
        // A file written before levels existed has no `levels` key at all.
        #expect(try read(manifest()).levels.isEmpty)
        #expect(throws: StoreSetError.unsupportedManifestVersion(3)) {
            try StoreManifest(json: Data(json.replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 3").utf8))
        }
    }

    @Test func aLevelThatDoesNotHoldTogetherIsRefused() throws {
        func refused(_ levels: [StoreManifest.Level], _ comment: Comment) throws {
            #expect(throws: StoreSetError.self, comment) { try read(manifest(levels: levels)) }
        }
        try refused([level(8), level(8, file: "levels/8b/8-140-75.gmk")], "a top zoom twice")
        try refused([level(0)], "top zoom 0")
        try refused([level(11)], "top zoom 11")
        var wrongStorage = level(8)
        wrongStorage.storageZoom = 9
        try refused([wrongStorage], "storage zoom is top zoom + 2")
        var tooFine = level(8)
        tooFine.storageZoom = 13
        tooFine.topZoom = 11
        try refused([tooFine], "a level must be coarser than the blocks")
        try refused([level(8, blockZoom: 9)], "a block zoom above that of the base blocks")
        try refused([level(8, file: "blocks/8-140-75.gmk")], "a file that a base block uses")
        try refused([level(8, file: "../levels/8-140-75.gmk")], "a file outside the folder")
        var duplicateClass = level(8)
        duplicateClass.classes = [3, 3]
        try refused([duplicateClass], "a class twice")
        var outsideOrigin = level(8)
        outsideOrigin.blocks[0].derivedFrom = [.init(x: 999, y: 75, bytes: 1)]
        try refused([outsideOrigin], "an origin outside the grid")
        var outsideTile = level(8)
        outsideTile.blocks[0].x = 300
        try refused([outsideTile], "a block outside the grid of the level")
    }

    @Test func theVersionFollowsTheLevelsAndALevelInAVersion1FileIsRefused() throws {
        #expect(manifest().version == 1 && manifest(levels: [level()]).version == 2)
        let json = String(decoding: try manifest(levels: [level()]).jsonData(), as: UTF8.self)
        #expect(throws: StoreSetError.self) {
            try StoreManifest(json: Data(json.replacingOccurrences(of: "\"version\" : 2", with: "\"version\" : 1").utf8))
        }
    }

    @Test func aLevelBlockIsStaleWhenABaseBlockItWasMadeFromChangedOrIsGone() throws {
        var current = manifest(levels: [level(8), level(7, file: "levels/7/8-140-75.gmk")])
        #expect(current.staleLevelBlocks().isEmpty)
        current.blocks[0].bytes += 1
        #expect(current.staleLevelBlocks() == [.init(topZoom: 8, x: 140, y: 75), .init(topZoom: 7, x: 140, y: 75)], "finest level first")
        current.blocks = []
        #expect(current.staleLevelBlocks().count == 2, "a base block that is gone")
    }

    @Test func aSetOpensAManifestWithLevelsAndStillReadsTheBlocks() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-levels-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let set = try StoreSet(manifest: manifest(levels: [level(8)]), directory: folder)
        #expect(set.manifest.levels.count == 1 && set.storageZoom == 13)
    }
}
