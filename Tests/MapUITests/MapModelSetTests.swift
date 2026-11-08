import FeatureStore
import Foundation
import GeoCore
import MapRender
import MapStyle
import Testing

@testable import MapUI

/// The model over a set of block files: a road that runs from one block into the next is drawn in one frame.
@MainActor
@Suite("MapModel over blocks")
struct MapModelSetTests {
    /// Cells on both sides of a border of the zoom 8 block grid, at about 60 degrees north.
    private let west = TileID(zoom: 13, x: 32 * 4 + 31, y: 32 * 74 + 5)!
    private let east = TileID(zoom: 13, x: 32 * 5, y: 32 * 74 + 5)!

    private func writer() -> FeatureStoreWriter {
        FeatureStoreWriter(
            boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: "© OpenStreetMap contributors, ODbL",
            classifierVersion: 16)
    }

    /// Two block files with the halves of one road, and a set over them in a new folder.
    private func blocks() throws -> (StoreSet, Coordinate, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-ui-set-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let border = Int32((east.northWest.longitude * 1e7).rounded())
        let latitude = Int32(((east.northWest.latitude + east.southEast.latitude) / 2 * 1e7).rounded())
        func line(_ xs: [Int32]) -> GeometryPart { GeometryPart(points: xs.map { PackedPoint(longitude: $0, latitude: latitude) }) }
        var a = writer(), b = writer()
        for band in [ZoomBand.mid, .detail] {
            try a.add(
                StoredFeature(
                    classID: FeatureClass.roadMajor.rawValue, kind: .line, objectType: .way, objectID: 1, flags: [.continuesAfter],
                    parts: [line([border - 20_000, border])]), band: band, cell: west)
            try b.add(
                StoredFeature(
                    classID: FeatureClass.roadMajor.rawValue, kind: .line, objectType: .way, objectID: 1, flags: [.continuesBefore],
                    offsetAlongLine: 20_000, parts: [line([border, border + 20_000])]), band: band, cell: east)
        }
        try a.data().write(to: folder.appendingPathComponent("west.gmk"))
        try b.data().write(to: folder.appendingPathComponent("east.gmk"))
        let format = try FeatureStoreFile(data: try a.data()).formatVersion
        let manifest = StoreManifest(
            formatVersion: format, classifierVersion: 16, storageZoom: 13, blockZoom: 8, bands: [.mid, .detail], profile: "full",
            attribution: "© OpenStreetMap contributors, ODbL",
            blocks: [
                StoreManifest.Block(x: 4, y: 74, file: "west.gmk", bytes: Int64(try a.data().count), builtAt: Date()),
                StoreManifest.Block(x: 5, y: 74, file: "east.gmk", bytes: Int64(try b.data().count), builtAt: Date()),
            ])
        let centre = Coordinate(latitude: Double(latitude) * 1e-7, longitude: Double(border) * 1e-7)
        return (try StoreSet(manifest: manifest, directory: folder), centre, folder)
    }

    private func waitForFrame(_ model: MapModel) async throws -> MapFrame {
        for _ in 0..<200 {
            if let frame = model.frame { return frame }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw MapRenderError.noBands
    }

    @Test func aFrameAcrossTheSeamIsDrawnFromBothBlocks() async throws {
        let (set, centre, folder) = try blocks()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = MapModel(source: set, style: .standard)
        model.request(viewport: MapViewport(center: centre, zoom: 17, width: 200, height: 100), scale: 1, interacting: false)
        let frame = try await waitForFrame(model)
        #expect(model.errorDescription == nil)
        #expect(set.openBlockCount == 2, "both blocks were needed")
        // The same view of the same cells as one scene: the road is one line that crosses the middle of the view.
        let scene = try MapSceneBuilder(source: set, style: .standard).scene(for: frame.viewport)
        let road = try #require(scene.steps.first { $0.step.featureClass == .roadMajor }?.lines)
        #expect(road.count == 1 && road[0].points.count == 3)
    }

    @Test func aMissingBlockShowsTheReasonInsteadOfAMap() async throws {
        let (set, centre, folder) = try blocks()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.removeItem(at: folder.appendingPathComponent("east.gmk"))
        let model = MapModel(source: set, style: .standard)
        model.request(viewport: MapViewport(center: centre, zoom: 17, width: 200, height: 100), scale: 1, interacting: false)
        for _ in 0..<200 where model.errorDescription == nil { try await Task.sleep(for: .milliseconds(25)) }
        #expect(model.frame == nil)
        #expect(model.errorDescription?.contains("east.gmk") == true && model.errorDescription?.contains("missing") == true)
    }

    @Test func aNewSourceDropsTheOldFrame() async throws {
        let (set, centre, folder) = try blocks()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = MapModel(source: set, style: .standard)
        model.request(viewport: MapViewport(center: centre, zoom: 17, width: 200, height: 100), scale: 1, interacting: false)
        _ = try await waitForFrame(model)
        model.update(source: set, style: .watch)
        #expect(model.frame == nil, "a frame of the old style is not shown")
    }
}
