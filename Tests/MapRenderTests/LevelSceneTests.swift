import FeatureStore
import Foundation
import GeoCore
import MapStyle
import Testing

@testable import MapRender

/// A map of a set with a coarse level reads the level at low zoom and the blocks at high zoom.
@Suite("Scenes from levels")
struct LevelSceneTests {
    private let cell13 = TileID(zoom: 13, x: 32 * 140 + 3, y: 32 * 75 + 3)!
    private let cell10 = TileID(zoom: 10, x: 4 * 140 + 1, y: 4 * 75 + 1)!

    private func road(_ cell: TileID, to writer: inout FeatureStoreWriter, band: ZoomBand) throws {
        let west = Int32((cell.northWest.longitude * 1e7).rounded()), east = Int32((cell.southEast.longitude * 1e7).rounded())
        let lat = Int32((cell.northWest.latitude * 1e7).rounded()) / 2 + Int32((cell.southEast.latitude * 1e7).rounded()) / 2
        try writer.add(
            StoredFeature(
                classID: FeatureClass.roadMajor.rawValue, kind: .line, objectType: .way, objectID: 1,
                parts: [GeometryPart(points: [PackedPoint(longitude: west + 100, latitude: lat), PackedPoint(longitude: east - 100, latitude: lat)])]),
            band: band, cell: cell)
    }

    private func set() throws -> (StoreSet, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-level-scene-\(UUID().uuidString)")
        for sub in ["blocks", "levels/8"] { try FileManager.default.createDirectory(at: folder.appendingPathComponent(sub), withIntermediateDirectories: true) }
        func writer(_ zoom: Int) -> FeatureStoreWriter {
            FeatureStoreWriter(
                storageZoom: zoom, boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: "© OpenStreetMap contributors, ODbL",
                classifierVersion: 18)
        }
        var base = writer(13), level = writer(10)
        for band in [ZoomBand.overview, .mid, .detail] { try road(cell13, to: &base, band: band) }
        try road(cell10, to: &level, band: .overview)
        let baseData = try base.data(), levelData = try level.data()
        try baseData.write(to: folder.appendingPathComponent("blocks/8-140-75.gmk"))
        try levelData.write(to: folder.appendingPathComponent("levels/8/8-140-75.gmk"))
        var manifest = StoreManifest(
            formatVersion: try FeatureStoreFile(data: baseData).formatVersion, classifierVersion: 18, storageZoom: 13, blockZoom: 8,
            bands: [.overview, .mid, .detail], profile: "full", attribution: "© OpenStreetMap contributors, ODbL",
            blocks: [StoreManifest.Block(x: 140, y: 75, file: "blocks/8-140-75.gmk", bytes: Int64(baseData.count), builtAt: Date())])
        manifest.levels = [
            StoreManifest.Level(
                topZoom: 8, blockZoom: 8, classes: [3],
                blocks: [StoreManifest.LevelBlock(
                    x: 140, y: 75, file: "levels/8/8-140-75.gmk", bytes: Int64(levelData.count), builtAt: Date(),
                    derivedFrom: [.init(x: 140, y: 75, bytes: Int64(baseData.count))])])
        ]
        return (try StoreSet(manifest: manifest, directory: folder), folder)
    }

    @Test func aWideViewReadsTheLevelAndANarrowViewReadsTheBlocks() throws {
        let (set, folder) = try set()
        defer { try? FileManager.default.removeItem(at: folder) }
        let centre = Coordinate(
            latitude: (cell10.northWest.latitude + cell10.southEast.latitude) / 2,
            longitude: (cell10.northWest.longitude + cell10.southEast.longitude) / 2)
        let builder = MapSceneBuilder(source: set, style: .standard)

        let wide = try builder.scene(for: MapViewport(center: centre, zoom: 7, width: 300, height: 200))
        #expect(wide.band == .overview && wide.cellCount == 1)
        #expect(wide.steps.contains { $0.step.featureClass == .roadMajor && !$0.lines.isEmpty })
        #expect(set.openBlockCount == 0, "the blocks of zoom 13 were not touched")

        let narrow = try builder.scene(for: MapViewport(center: centre, zoom: 14, width: 300, height: 200))
        #expect(narrow.band == .mid && set.openBlockCount == 1)
        #expect(narrow.attribution == wide.attribution)
    }

    @Test func aLevelThatIsOutOfDateIsAnErrorNotAWrongMap() throws {
        let (set, folder) = try set()
        defer { try? FileManager.default.removeItem(at: folder) }
        var manifest = set.manifest
        manifest.blocks[0].bytes += 3   // another build of the block
        let stale = try StoreSet(manifest: manifest, directory: folder)
        let centre = Coordinate(
            latitude: (cell10.northWest.latitude + cell10.southEast.latitude) / 2,
            longitude: (cell10.northWest.longitude + cell10.southEast.longitude) / 2)
        #expect(throws: StoreSetError.self) {
            try MapSceneBuilder(source: stale, style: .standard).scene(for: MapViewport(center: centre, zoom: 7, width: 300, height: 200))
        }
    }
}
