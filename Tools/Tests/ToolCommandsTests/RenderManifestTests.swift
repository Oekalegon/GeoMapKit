import FeatureStore
import Foundation
import GeoCore
import MapBuilder
import Regions
import Testing
import ToolSupport
@testable import ToolCommands

/// `render` over the manifest of a set of blocks that `build-region` made.
@Suite("render a manifest")
struct RenderManifestTests {
    private struct Catalog: RegionCatalog {
        func index() async throws -> RegionIndex {
            let ring = [Coordinate(latitude: 46, longitude: 8), Coordinate(latitude: 46, longitude: 10.5), Coordinate(latitude: 49, longitude: 10.5), Coordinate(latitude: 49, longitude: 8)]
            return try RegionIndex(regions: [SourceRegion(
                id: "tiny", name: "Tiny", parentID: nil, pbfURL: URL(string: "https://download.example.org/tiny.osm.pbf")!,
                outline: [RegionPolygon(outer: ring)])])
        }
    }

    @Test("render draws a map from the manifest of a set of blocks")
    func rendersAManifest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-render-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = SourceCache(directory: root.appendingPathComponent("cache"))
        let data = try TinyPBF.make()
        let part = try cache.preparePart(regionID: "tiny", etag: "\"e\"", keepBytes: false)
        try data.write(to: part)
        try cache.install(
            regionID: "tiny", from: URL(string: "https://download.example.org/tiny.osm.pbf")!,
            info: RemoteFileInfo(size: Int64(data.count), etag: "\"e\""))
        let report = try await MapBuilder.buildRegion(
            BlockRequest(
                area: .box(BoundingBox(south: 47, west: 9, north: 48, east: 10)), output: root.appendingPathComponent("blocks"),
                blockZoom: 8, margin: 0.1, cacheDirectory: root.appendingPathComponent("cache")),
            catalog: Catalog())
        let set = try StoreSet(manifestURL: report.manifestURL)
        let box = try #require(set.boundingBox)
        let png = root.appendingPathComponent("m.png")
        let centre = Coordinate(latitude: (box.south + box.north) / 2, longitude: (box.west + box.east) / 2)
        let rendered = try ToolRunner.render(
            store: report.manifestURL, request: RenderRequest(center: centre, zoom: 9, width: 200, height: 150, scale: 1, style: .standard, output: png.path))
        #expect(Array(try Data(contentsOf: png).prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
        #expect(rendered.pixelWidth == 200 && rendered.cellCount > 0)
    }
}
