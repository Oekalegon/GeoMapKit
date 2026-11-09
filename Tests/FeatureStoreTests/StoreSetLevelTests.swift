import Foundation
import GeoCore
import Testing

@testable import FeatureStore

/// Reading the coarse levels of a set: which level serves a zoom, and what a level block has to be.
@Suite("Store set levels")
struct StoreSetLevelTests {
    /// The base block (140, 75) of zoom 8, a level 8 (cells of zoom 10) and a level 6 (cells of zoom 8), each with one road.
    private struct Fixture {
        let folder: URL
        let manifest: StoreManifest
        /// A cell of zoom 10 inside the block, a cell of zoom 8 (the block) and a cell of zoom 13 inside the block.
        let cell10 = TileID(zoom: 10, x: 4 * 140 + 1, y: 4 * 75 + 1)!
        let cell8 = TileID(zoom: 8, x: 140, y: 75)!
        let cell13 = TileID(zoom: 13, x: 32 * 140 + 3, y: 32 * 75 + 3)!
    }

    private func writer(zoom: Int) -> FeatureStoreWriter {
        FeatureStoreWriter(
            storageZoom: zoom, boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: "© OpenStreetMap contributors, ODbL",
            classifierVersion: 18)
    }

    private func road(_ cell: TileID, band: ZoomBand, to writer: inout FeatureStoreWriter) throws {
        let west = Int32((cell.northWest.longitude * 1e7).rounded()), east = Int32((cell.southEast.longitude * 1e7).rounded())
        let lat = Int32((cell.northWest.latitude * 1e7).rounded()) / 2 + Int32((cell.southEast.latitude * 1e7).rounded()) / 2
        try writer.add(
            StoredFeature(
                classID: FeatureClass.roadMajor.rawValue, kind: .line, objectType: .way, objectID: Int64(cell.zoom),
                parts: [GeometryPart(points: [PackedPoint(longitude: west + 100, latitude: lat), PackedPoint(longitude: east - 100, latitude: lat)])]),
            band: band, cell: cell)
    }

    /// Writes the files and the manifest. `tweak` changes the manifest before it is used.
    private func fixture(
        levelBand: ZoomBand = .overview, level8Zoom: Int = 10, tweak: (inout StoreManifest) -> Void = { _ in }
    ) throws -> (Fixture, StoreSet) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-levels-read-\(UUID().uuidString)")
        for sub in ["blocks", "levels/8", "levels/6"] { try FileManager.default.createDirectory(at: folder.appendingPathComponent(sub), withIntermediateDirectories: true) }
        let probe = Fixture(folder: folder, manifest: StoreManifest(formatVersion: 1, classifierVersion: 18, storageZoom: 13, blockZoom: 8, bands: [.overview], profile: "full", attribution: "", blocks: []))
        var base = writer(zoom: 13), level8 = writer(zoom: level8Zoom), level6 = writer(zoom: 8)
        try road(probe.cell13, band: .overview, to: &base)
        try road(probe.cell13, band: .detail, to: &base)
        try road(level8Zoom == 10 ? probe.cell10 : TileID(zoom: level8Zoom, x: 8 * 140 + 1, y: 8 * 75 + 1)!, band: levelBand, to: &level8)
        try road(probe.cell8, band: .overview, to: &level6)
        let baseData = try base.data(), level8Data = try level8.data(), level6Data = try level6.data()
        try baseData.write(to: folder.appendingPathComponent("blocks/8-140-75.gmk"))
        try level8Data.write(to: folder.appendingPathComponent("levels/8/8-140-75.gmk"))
        try level6Data.write(to: folder.appendingPathComponent("levels/6/8-140-75.gmk"))
        let origin = StoreManifest.LevelBlock.Origin(x: 140, y: 75, bytes: Int64(baseData.count))
        var manifest = StoreManifest(
            formatVersion: try FeatureStoreFile(data: baseData).formatVersion, classifierVersion: 18, storageZoom: 13, blockZoom: 8,
            bands: [.overview, .mid, .detail], profile: "full", attribution: "© OpenStreetMap contributors, ODbL",
            blocks: [StoreManifest.Block(x: 140, y: 75, file: "blocks/8-140-75.gmk", bytes: Int64(baseData.count), builtAt: Date())])
        manifest.levels = [
            StoreManifest.Level(
                topZoom: 8, blockZoom: 8, classes: [3],
                blocks: [StoreManifest.LevelBlock(x: 140, y: 75, file: "levels/8/8-140-75.gmk", bytes: Int64(level8Data.count), builtAt: Date(), derivedFrom: [origin])]),
            StoreManifest.Level(
                topZoom: 6, blockZoom: 8, classes: [3],
                blocks: [StoreManifest.LevelBlock(x: 140, y: 75, file: "levels/6/8-140-75.gmk", bytes: Int64(level6Data.count), builtAt: Date(), derivedFrom: [origin])]),
        ]
        tweak(&manifest)
        return (Fixture(folder: folder, manifest: manifest), try StoreSet(manifest: manifest, directory: folder))
    }

    @Test func theLevelThatServesAZoomIsTheNextFinerOneAndTheBlocksServeTheRest() throws {
        let (f, set) = try fixture()
        defer { try? FileManager.default.removeItem(at: f.folder) }
        #expect(set.levelName(forZoom: 2) == "level 6", "below the coarsest level")
        #expect(set.levelName(forZoom: 5.9) == "level 6" && set.levelName(forZoom: 6) == "level 6")
        #expect(set.levelName(forZoom: 6.01) == "level 8" && set.levelName(forZoom: 7) == "level 8" && set.levelName(forZoom: 8) == "level 8")
        #expect(set.levelName(forZoom: 8.01) == "blocks" && set.levelName(forZoom: 12) == "blocks" && set.levelName(forZoom: 20) == "blocks")
        #expect(set.source(atZoom: 12).storageZoom == 13 && set.source(atZoom: 7).storageZoom == 10 && set.source(atZoom: 3).storageZoom == 8)
        // A set without levels is its own source.
        var plain = f.manifest
        plain.levels = []
        let none = try StoreSet(manifest: plain, directory: f.folder)
        #expect(none.levelName(forZoom: 3) == "blocks" && none.source(atZoom: 3).storageZoom == 13)
        // A single file is its own source at every zoom.
        let file = try FeatureStoreFile(contentsOf: f.folder.appendingPathComponent("blocks/8-140-75.gmk"))
        #expect(file.source(atZoom: 2).storageZoom == 13)
    }

    @Test func aLevelHandsOutItsCellsAndOnlyThose() throws {
        let (f, set) = try fixture()
        defer { try? FileManager.default.removeItem(at: f.folder) }
        let level = try #require(set.level(forZoom: 7))
        #expect(level.storageZoom == 10 && level.bands == [.overview] && level.attribution == "© OpenStreetMap contributors, ODbL")
        #expect(try level.file(containing: f.cell10)?.cells() == [f.cell10])
        #expect(try level.file(containing: TileID(zoom: 10, x: 4 * 140 + 2, y: 4 * 75 + 2)!) == nil, "a cell the file does not hold")
        #expect(try level.file(containing: TileID(zoom: 10, x: 4 * 141, y: 4 * 75)!) == nil, "a block that is not in the level")
        #expect(try level.file(containing: f.cell13) == nil, "a cell of another zoom")
        #expect(level.openBlockCount == 1 && set.openBlockCount == 0, "a level does not open the base blocks")
        // The blocks are read as before.
        #expect(try set.file(containing: f.cell13) != nil && set.openBlockCount == 1)
    }

    @Test func aLevelBlockThatIsMissingDamagedOrNotWhatTheManifestSaysIsAnError() throws {
        // Missing.
        var (f, set) = try fixture()
        try FileManager.default.removeItem(at: f.folder.appendingPathComponent("levels/8/8-140-75.gmk"))
        #expect(throws: StoreSetError.blockMissing("levels/8/8-140-75.gmk")) { try set.level(forZoom: 7)?.file(containing: f.cell10) }
        try? FileManager.default.removeItem(at: f.folder)
        // Another size than the manifest says.
        (f, set) = try fixture { $0.levels[0].blocks[0].bytes += 1 }
        #expect(throws: StoreSetError.self) { try set.level(forZoom: 7)?.file(containing: f.cell10) }
        try? FileManager.default.removeItem(at: f.folder)
        // Another storage zoom than the level has.
        (f, set) = try fixture(level8Zoom: 11)
        #expect(throws: StoreSetError.self) { try set.level(forZoom: 7)?.file(containing: f.cell10) }
        try? FileManager.default.removeItem(at: f.folder)
        // A band that a level does not hold.
        (f, set) = try fixture(levelBand: .mid)
        #expect(throws: StoreSetError.self) { try set.level(forZoom: 7)?.file(containing: f.cell10) }
        try? FileManager.default.removeItem(at: f.folder)
        // Another rule table than the blocks.
        (f, set) = try fixture { $0.classifierVersion = 17 }
        #expect(throws: StoreSetError.self) { try set.level(forZoom: 7)?.file(containing: f.cell10) }
        try? FileManager.default.removeItem(at: f.folder)
    }

    @Test func aLevelBlockMadeFromBlocksThatHaveChangedIsRefusedWithAPointerToBuildLevels() throws {
        // The base block is another build now: it has another size in the manifest than the level block recorded.
        let (f, set) = try fixture { manifest in
            let size = manifest.blocks[0].bytes
            manifest.blocks[0].bytes = size + 5
        }
        defer { try? FileManager.default.removeItem(at: f.folder) }
        #expect(throws: StoreSetError.levelOutOfDate(file: "levels/8/8-140-75.gmk")) { try set.level(forZoom: 7)?.file(containing: f.cell10) }
        #expect("\(StoreSetError.levelOutOfDate(file: "levels/8/8-140-75.gmk"))".contains("geomapkit build-levels"))
        // The level that was not made from a changed block would be fine: here both are stale.
        #expect(throws: StoreSetError.self) { try set.level(forZoom: 3)?.file(containing: f.cell8) }
    }

    @Test func aLevelKeepsAtMostTheOpenBlocksItIsGivenAndSurvivesThreads() throws {
        let (f, base) = try fixture()
        defer { try? FileManager.default.removeItem(at: f.folder) }
        // A second level block (the file is a copy; its cells do not matter) and a set that may keep one block open.
        try FileManager.default.copyItem(at: f.folder.appendingPathComponent("levels/8/8-140-75.gmk"), to: f.folder.appendingPathComponent("levels/8/8-141-75.gmk"))
        var manifest = base.manifest
        let first = manifest.levels[0].blocks[0]
        manifest.levels[0].blocks.append(
            StoreManifest.LevelBlock(x: 141, y: 75, file: "levels/8/8-141-75.gmk", bytes: first.bytes, builtAt: Date(), derivedFrom: first.derivedFrom))
        let set = try StoreSet(manifest: manifest, directory: f.folder, maximumOpenBlocks: 1)
        let level = try #require(set.level(forZoom: 7))
        let other = TileID(zoom: 10, x: 4 * 141 + 1, y: 4 * 75 + 1)!
        _ = try level.file(containing: f.cell10)
        #expect(level.openBlockCount == 1)
        _ = try level.file(containing: other)
        #expect(level.openBlockCount == 1, "the least recently used block was closed")
        // Many threads asking for both blocks at once: no crash, the limit holds, and the right cell is found.
        let found = LockedCounter()
        DispatchQueue.concurrentPerform(iterations: 200) { index in
            let cell = index.isMultiple(of: 2) ? f.cell10 : other
            if let file = try? level.file(containing: cell), (try? file.containsCell(cell)) == true { found.increment() }
        }
        #expect(found.value == 100 && level.openBlockCount <= 1)
    }

    @Test func aZoomThatIsNotANumberIsServedByTheBlocks() throws {
        let (f, set) = try fixture()
        defer { try? FileManager.default.removeItem(at: f.folder) }
        #expect(set.levelName(forZoom: .nan) == "blocks")
        #expect(set.levelName(forZoom: .infinity) == "blocks" && set.levelName(forZoom: -.infinity) == "level 6")
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
