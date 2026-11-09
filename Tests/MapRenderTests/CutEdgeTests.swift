import FeatureStore
import Foundation
import GeoCore
import MapStyle
import Testing

@testable import MapRender

/// A copy for the Watch ends at a cell edge: what continues past the edge must end there like the edge of any map, with no false end
/// and no stroke along an edge that only the cut made.
@Suite("The edge of a cut copy")
struct CutEdgeTests {
    private let west = TileID(zoom: 13, x: 32 * 4 + 31, y: 32 * 74 + 5)!
    private let east = TileID(zoom: 13, x: 32 * 5, y: 32 * 74 + 5)!

    private var latitude: Int32 { Int32(((east.northWest.latitude + east.southEast.latitude) / 2 * 1e7).rounded()) }
    private var border: Int32 { Int32((east.northWest.longitude * 1e7).rounded()) }

    private func source() throws -> FeatureStoreFile {
        var writer = FeatureStoreWriter(
            boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: "© OpenStreetMap contributors, ODbL",
            classifierVersion: 20)
        let latitude = latitude, border = border
        for band in [ZoomBand.mid, .detail] {
            try writer.add(
                StoredFeature(
                    classID: FeatureClass.roadMajor.rawValue, kind: .line, objectType: .way, objectID: 100, flags: [.continuesAfter],
                    parts: [GeometryPart(points: [PackedPoint(longitude: border - 3_000, latitude: latitude), PackedPoint(longitude: border, latitude: latitude)])]),
                band: band, cell: west)
            try writer.add(
                StoredFeature(
                    classID: FeatureClass.roadMajor.rawValue, kind: .line, objectType: .way, objectID: 100, flags: [.continuesBefore], offsetAlongLine: 30_000,
                    parts: [GeometryPart(points: [PackedPoint(longitude: border, latitude: latitude), PackedPoint(longitude: border + 3_000, latitude: latitude)])]),
                band: band, cell: east)
            // A lake that goes on over the border: the edge on the border belongs to the cell, not to the lake.
            let lake = GeometryPart(
                points: [
                    PackedPoint(longitude: border - 1_500, latitude: latitude + 800), PackedPoint(longitude: border, latitude: latitude + 800),
                    PackedPoint(longitude: border, latitude: latitude + 1_500), PackedPoint(longitude: border - 1_500, latitude: latitude + 1_500),
                    PackedPoint(longitude: border - 1_500, latitude: latitude + 800),
                ], artificialEdges: [1..<2])
            try writer.add(
                StoredFeature(classID: FeatureClass.waterArea.rawValue, kind: .area, objectType: .way, objectID: 300, parts: [lake]),
                band: band, cell: west)
        }
        return try FeatureStoreFile(data: writer.data())
    }

    @Test("The copy of the west cell draws the road and the lake like the map did in that cell")
    func sameAsTheMapInTheCell() throws {
        let original = try source()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-edge-\(UUID().uuidString).gmk")
        defer { try? FileManager.default.removeItem(at: url) }
        let area = BoundingBox(
            south: west.southEast.latitude + 0.0001, west: west.northWest.longitude + 0.0001, north: west.northWest.latitude - 0.0001,
            east: west.southEast.longitude - 0.0001)
        try RegionCutter(source: original).cut(area: area, to: url)
        let copy = try FeatureStoreFile(contentsOf: url)
        // A view that shows the west cell and a little of the east one, which the copy does not have.
        let view = MapViewport(
            center: Coordinate(latitude: Double(latitude) * 1e-7, longitude: Double(border - 1_000) * 1e-7), zoom: 17, width: 400, height: 400)
        let before = try MapSceneBuilder(file: original, style: .standard).scene(for: view)
        let after = try MapSceneBuilder(file: copy, style: .standard).scene(for: view)
        for step in [DrawStep(featureClass: .roadMajor, part: .body), DrawStep(featureClass: .waterArea, part: .body)] {
            let a = before.steps.first { $0.step == step }, b = after.steps.first { $0.step == step }
            #expect(a != nil && b != nil, "\(step) is drawn")
            // The original also has the east cell (the road goes on over the border); the copy ends at the border.
            #expect(b?.lines.count == a?.lines.count, "\(step): the same number of lines")
        }
        let road = try #require(after.steps.first { $0.step == DrawStep(featureClass: .roadMajor, part: .body) }?.lines.first)
        #expect(road.points.count == 2, "the road ends at the border of the copy with its own two points, no piece is added")
    }
}
