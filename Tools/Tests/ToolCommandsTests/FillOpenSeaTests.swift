import FeatureStore
import FeatureStoreBuilder
import Foundation
import GeoCore
import Regions
import ToolSupport
import Testing

@testable import FeatureStoreBuilder
@testable import ToolCommands

/// The open sea between the blocks of a set that no region below a continent touches.
@Suite("Fill open sea")
struct FillOpenSeaTests {
    private struct FixedCatalog: RegionCatalog {
        let regions: [SourceRegion]
        func index() async throws -> RegionIndex { try RegionIndex(regions: regions) }
    }

    private func region(_ id: String, parent: String?, _ tile: TileID?) -> SourceRegion {
        let (west, south, east, north): (Double, Double, Double, Double)
        if let tile {
            (west, south, east, north) = (tile.northWest.longitude, tile.southEast.latitude, tile.southEast.longitude, tile.northWest.latitude)
        } else {
            (west, south, east, north) = (-60, 30, 60, 75)
        }
        let ring = [
            Coordinate(latitude: south, longitude: west), Coordinate(latitude: south, longitude: east),
            Coordinate(latitude: north, longitude: east), Coordinate(latitude: north, longitude: west),
        ]
        return SourceRegion(
            id: id, name: id, parentID: parent, pbfURL: URL(string: "https://download.example.org/\(id).osm.pbf")!, outline: [RegionPolygon(outer: ring)])
    }

    private func block(x: Int, y: Int, sea: Bool, in folder: URL) throws -> StoreManifest.Block {
        var writer = FeatureStoreWriter(
            boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: "© OpenStreetMap contributors, ODbL", classifierVersion: 16)
        let first = TileID(zoom: 13, x: x * 32, y: y * 32)!
        let rect = CellRect(tile: first)
        let lat = (rect.north + rect.south) / 2
        let coast = StoredFeature(
            classID: FeatureClass.coastline.rawValue, kind: .line, objectType: .way, objectID: 7,
            parts: [GeometryPart(points: [PackedPoint(longitude: rect.west, latitude: lat), PackedPoint(longitude: rect.east, latitude: lat)])])
        try writer.add(coast, band: .overview, cell: first)
        if sea {
            for dy in 0..<32 {
                for dx in 0..<32 {
                    let cell = TileID(zoom: 13, x: x * 32 + dx, y: y * 32 + dy)!
                    let square = StoredFeature(
                        classID: FeatureClass.sea.rawValue, kind: .area, objectType: .way, objectID: 0,
                        parts: [SeaBuilder.wholeCell(CellRect(tile: cell))])
                    for band in [ZoomBand.overview, .mid, .detail] { try writer.add(square, band: band, cell: cell) }
                }
            }
        } else {
            // Land: a forest in every cell (a cell with no sea counts as land only when something on it lies on land).
            for dy in 0..<32 {
                for dx in 0..<32 {
                    let cell = TileID(zoom: 13, x: x * 32 + dx, y: y * 32 + dy)!
                    let forest = StoredFeature(
                        classID: FeatureClass.forest.rawValue, kind: .area, objectType: .way, objectID: 3,
                        parts: [SeaBuilder.wholeCell(CellRect(tile: cell))])
                    for band in [ZoomBand.overview, .mid, .detail] { try writer.add(forest, band: band, cell: cell) }
                }
            }
        }
        let name = "blocks/8-\(x)-\(y).gmk"
        let data = try writer.data()
        try data.write(to: folder.appendingPathComponent(name))
        return StoreManifest.Block(x: x, y: y, file: name, bytes: Int64(data.count), builtAt: Date(timeIntervalSince1970: 0))
    }

    @Test("Blocks between a sea block and a land block that only a continent covers become sea, and a second run changes nothing")
    func fillsTheHole() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fillsea-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("blocks"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let seaBlock = try block(x: 130, y: 80, sea: true, in: folder)
        let landBlock = try block(x: 133, y: 80, sea: false, in: folder)
        let format = try FeatureStoreFile(
            data: FeatureStoreWriter(boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: "").data()
        ).formatVersion
        let manifest = StoreManifest(
            formatVersion: format, classifierVersion: 16, storageZoom: 13, blockZoom: 8, bands: [.overview, .mid, .detail],
            profile: "full", attribution: "© OpenStreetMap contributors, ODbL", blocks: [seaBlock, landBlock])
        try manifest.jsonData().write(to: folder.appendingPathComponent("manifest.json"))
        // The continent covers everything; only the country covers the land block.
        let catalog = FixedCatalog(regions: [region("europe", parent: nil, nil), region("country", parent: "europe", TileID(zoom: 8, x: 133, y: 80))])

        let report = try await ToolRunner.fillOpenSea(folder: folder, cacheDirectory: folder, catalog: catalog)
        #expect(Set(report.created.map { [$0.x, $0.y] }) == [[131, 80], [132, 80]])
        let written = try StoreManifest(json: try Data(contentsOf: folder.appendingPathComponent("manifest.json")))
        try written.validate()
        #expect(written.blocks.count == 4)

        let again = try await ToolRunner.fillOpenSea(folder: folder, cacheDirectory: folder, catalog: catalog)
        #expect(!again.changed)
    }

    @Test("A top-level region with no regions below it is data too: the blocks it covers are not sea")
    func aTopLevelLeafCounts() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fillsea-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("blocks"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let seaBlock = try block(x: 130, y: 80, sea: true, in: folder)
        let landBlock = try block(x: 133, y: 80, sea: false, in: folder)
        let format = try FeatureStoreFile(
            data: FeatureStoreWriter(boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: "").data()
        ).formatVersion
        let manifest = StoreManifest(
            formatVersion: format, classifierVersion: 16, storageZoom: 13, blockZoom: 8, bands: [.overview, .mid, .detail],
            profile: "full", attribution: "© OpenStreetMap contributors, ODbL", blocks: [seaBlock, landBlock])
        try manifest.jsonData().write(to: folder.appendingPathComponent("manifest.json"))
        // A country with no parent and no children (an island state) that covers the blocks between: they are its land, not open sea.
        let island = SourceRegion(
            id: "island-state", name: "Island state", parentID: nil, pbfURL: URL(string: "https://download.example.org/i.osm.pbf")!,
            outline: [RegionPolygon(outer: [
                Coordinate(latitude: 40, longitude: 0), Coordinate(latitude: 40, longitude: 60), Coordinate(latitude: 75, longitude: 60),
                Coordinate(latitude: 75, longitude: 0),
            ])])
        let catalog = FixedCatalog(regions: [region("europe", parent: nil, nil), region("state", parent: "europe", TileID(zoom: 8, x: 133, y: 80)), island])
        let report = try await ToolRunner.fillOpenSea(folder: folder, cacheDirectory: folder, catalog: catalog)
        #expect(!report.changed)
    }

    @Test("A set of the Watch profile is refused")
    func refusesTheWatchProfile() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fillsea-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("blocks"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let one = try block(x: 130, y: 80, sea: true, in: folder)
        let format = try FeatureStoreFile(
            data: FeatureStoreWriter(boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: "").data()
        ).formatVersion
        let manifest = StoreManifest(
            formatVersion: format, classifierVersion: 16, storageZoom: 13, blockZoom: 8, bands: [.overview, .mid, .detail],
            profile: "watch", attribution: "© OpenStreetMap contributors, ODbL", blocks: [one])
        try manifest.jsonData().write(to: folder.appendingPathComponent("manifest.json"))
        await #expect(throws: ToolError.self) {
            try await ToolRunner.fillOpenSea(folder: folder, cacheDirectory: folder, catalog: FixedCatalog(regions: [self.region("europe", parent: nil, nil)]))
        }
    }
}
