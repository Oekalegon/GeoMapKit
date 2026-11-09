import Foundation
import GeoCore
import Testing

@testable import FeatureStore

/// Tags are stored in the detail band only, except for `landUse`, which keeps its tags in every band.
@Suite("Tags per band")
struct CellCodecTagsTests {
    @Test("A landUse feature keeps its tag in the mid band, another class loses its tags there")
    func landUseKeepsTags() throws {
        var writer = FeatureStoreWriter(boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: "")
        let cell = try #require(TileID(zoom: 13, x: 4_000, y: 2_400))
        let point = GeometryPart(points: [PackedPoint(longitude: 1, latitude: 1)])
        let tag = StoredTag(key: writer.intern("landuse"), value: writer.intern("landfill"))
        for (id, featureClass) in [(Int64(1), FeatureClass.landUse), (2, FeatureClass.landcover)] {
            try writer.add(
                StoredFeature(classID: featureClass.rawValue, kind: .point, objectType: .node, objectID: id, tags: [tag], parts: [point]),
                band: .mid, cell: cell)
            try writer.add(
                StoredFeature(classID: featureClass.rawValue, kind: .point, objectType: .node, objectID: id, tags: [tag], parts: [point]),
                band: .detail, cell: cell)
        }
        let file = try FeatureStoreFile(data: try writer.data())
        let mid = try file.features(in: cell, band: .mid)
        #expect(mid.first { $0.objectID == 1 }?.tags == [tag], "landUse: the tag in the mid band")
        #expect(mid.first { $0.objectID == 2 }?.tags.isEmpty == true, "landcover: no tags in the mid band")
        let detail = try file.features(in: cell, band: .detail)
        #expect(detail.allSatisfy { $0.tags == [tag] })
    }
}
