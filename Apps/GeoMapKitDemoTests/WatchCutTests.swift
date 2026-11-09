import FeatureStore
import Foundation
import GeoCore
import Testing

@testable import GeoMapKitDemo

@Suite("Watch cut")
struct WatchCutTests {
    @Test func theAreaIsASquareOfTheGivenSideAroundThePosition() {
        let box = WatchCut.area(around: Coordinate(latitude: 60, longitude: 10), kilometres: 10)
        // 10 km is 0.0899 degrees of latitude, and twice that of longitude at 60 degrees north.
        #expect(abs((box.north - box.south) - 10 / 111.32) < 1e-9)
        #expect(abs((box.east - box.west) - 2 * 10 / 111.32) < 1e-6)
        #expect(abs((box.north + box.south) / 2 - 60) < 1e-9 && abs((box.east + box.west) / 2 - 10) < 1e-9)
    }

    @Test func aMapWithNothingInTheAreaGivesASentence() throws {
        var writer = FeatureStoreWriter(boundingBox: BoundingBox(south: 59, west: 10, north: 60, east: 11), attribution: "x")
        let cell = try #require(TileID(zoom: 13, x: 4_300, y: 2_300))
        try writer.add(
            StoredFeature(
                classID: FeatureClass.path.rawValue, kind: .point, objectType: .node, objectID: 1,
                parts: [GeometryPart(points: [PackedPoint(longitude: 0, latitude: 0)])]),
            band: .mid, cell: cell)
        let source = try FeatureStoreFile(data: writer.data())
        do {
            _ = try WatchCut.cut(source: source, named: "T", around: Coordinate(latitude: 20, longitude: 20), kilometres: 3)
            Issue.record("expected an error")
        } catch {
            #expect(WatchCut.sentence(for: error).contains("nothing for the Watch"))
        }
    }
}
