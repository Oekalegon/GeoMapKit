import Foundation
import GeoCore
import Testing

@testable import FeatureStore

/// The tags of a feature are written as given, in every band.
@Suite("Tags per band")
struct CellCodecTagsTests {
    @Test("Tags are written as given in every band, for every class")
    func tagsAsGiven() throws {
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
        #expect(mid.first { $0.objectID == 2 }?.tags == [tag], "the file does not decide which band has tags; the builder does")
        let detail = try file.features(in: cell, band: .detail)
        #expect(detail.allSatisfy { $0.tags == [tag] })
    }
}
