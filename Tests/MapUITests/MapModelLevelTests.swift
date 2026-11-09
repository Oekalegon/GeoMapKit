import FeatureStore
import Foundation
import GeoCore
import MapRender
import MapStyle
import Testing

@testable import MapUI

/// The model draws a frame at low zoom from the coarse level of a set.
@MainActor
@Suite("MapModel over levels")
struct MapModelLevelTests {
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

    @Test func aFrameAtLowZoomComesFromTheLevelAndNeverOpensTheBlocks() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-ui-levels-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
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
        let set = try StoreSet(manifest: manifest, directory: folder)
        let centre = Coordinate(
            latitude: (cell10.northWest.latitude + cell10.southEast.latitude) / 2,
            longitude: (cell10.northWest.longitude + cell10.southEast.longitude) / 2)
        let model = MapModel(source: set, style: .standard)
        model.request(viewport: MapViewport(center: centre, zoom: 7, width: 300, height: 200), scale: 1, interacting: false)
        for _ in 0..<200 where model.frame == nil && model.errorDescription == nil { try await Task.sleep(for: .milliseconds(25)) }
        #expect(model.errorDescription == nil && model.frame != nil)
        #expect(set.openBlockCount == 0, "the blocks were not opened for a view at zoom 7")
    }
}
