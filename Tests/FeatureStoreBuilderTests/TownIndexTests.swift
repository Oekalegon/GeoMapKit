import FeatureStore
import Foundation
import GeoCore
import Testing

@testable import FeatureStoreBuilder

@Suite("Town index")
struct TownIndexTests {
    private func polygon(_ rings: [[(Double, Double)]]) throws -> TownIndex.Polygon {
        try #require(TownIndex.Polygon(rings: rings.map { $0.map { (x: $0.0, y: $0.1) } }))
    }

    @Test("Points in a concave polygon, in its notch, in its hole and outside it")
    func containment() throws {
        // A C shape open to the east: the notch is the square 2...4 x 2...4 reached from the east.
        let c = try polygon([[(0, 0), (6, 0), (6, 2), (2, 2), (2, 4), (6, 4), (6, 6), (0, 6), (0, 0)]])
        #expect(c.contains(x: 1, y: 3) && c.contains(x: 5, y: 1) && c.contains(x: 5, y: 5))
        #expect(!c.contains(x: 4, y: 3), "in the notch")
        #expect(!c.contains(x: 7, y: 3) && !c.contains(x: -1, y: 3) && !c.contains(x: 3, y: 7), "outside the box")
        // A square with a square hole: even-odd, so the hole is outside.
        let ring = try polygon([[(0, 0), (10, 0), (10, 10), (0, 10), (0, 0)], [(4, 4), (6, 4), (6, 6), (4, 6), (4, 4)]])
        #expect(ring.contains(x: 2, y: 2) && !ring.contains(x: 5, y: 5) && ring.contains(x: 8, y: 5))
        #expect(TownIndex.Polygon(rings: [[(x: 0, y: 0), (x: 1, y: 1)]]) == nil, "a ring with fewer than four points is not an area")
    }

    @Test("A polygon larger than the grid limit is still found, small ones too, and a miss is a miss")
    func largePolygons() throws {
        var layer = TownIndex.Layer()
        layer.add(try polygon([[(0, 0), (30_000, 0), (30_000, 30_000), (0, 30_000), (0, 0)]]))      // 90,000 cells: kept in the list
        layer.add(try polygon([[(40_000, 0), (40_050, 0), (40_050, 50), (40_000, 50), (40_000, 0)]]))  // one cell: in the grid
        #expect(layer.contains(x: 15_000, y: 15_000) && layer.contains(x: 29_999, y: 1))
        #expect(layer.contains(x: 40_025, y: 25))
        #expect(!layer.contains(x: 35_000, y: 10) && !layer.contains(x: -5, y: 5) && !layer.contains(x: 40_025, y: 75))
    }

    @Test("A flat projection scales east-west distances with the latitude")
    func projection() {
        let metres = LocalMetres()
        func eastWest(at latitude: Int32) -> Double {
            let a = metres.project(PackedPoint(longitude: 100_000_000, latitude: latitude))
            let b = metres.project(PackedPoint(longitude: 100_100_000, latitude: latitude))      // 0.01 degrees east
            return b.x - a.x
        }
        #expect(abs(eastWest(at: 0) - 1_111.95) < 1)
        #expect(abs(eastWest(at: 600_000_000) - 1_111.95 / 2) < 1, "half as far at 60 degrees")
        let north = metres.project(PackedPoint(longitude: 0, latitude: 100_000)).y - metres.project(PackedPoint(longitude: 0, latitude: 0)).y
        #expect(abs(north - 1_111.95) < 1)
    }

    private func classID(of id: Int64, in file: FeatureStoreFile) throws -> UInt8? {
        for cell in try file.cells() {
            if let feature = try file.features(in: cell, band: .detail).first(where: { $0.objectID == id && $0.objectType == .way }) {
                return feature.classID
            }
        }
        return nil
    }

    private func walk(_ world: inout SyntheticWorld, _ id: Int64, _ from: (Double, Double), _ to: (Double, Double)) {
        world.node(id * 10, from.0, from.1); world.node(id * 10 + 1, to.0, to.1)
        world.way(id, [id * 10, id * 10 + 1], [("highway", "footway")])
    }

    @Test("A park mapped as a relation is green: its paths stay paths inside the housing around it")
    func parkAsRelation() throws {
        var world = SyntheticWorld()
        world.way(500, world.rectangle(first: 500, 0.3, 0.3, 2.7, 2.7), [("landuse", "residential")])
        // The park: an untagged closed way held by a multipolygon relation that carries the tags.
        world.way(510, world.rectangle(first: 510, 0.5, 0.5, 1.5, 1.5))
        world.relation(1_000, [(510, "outer", 1)], [("type", "multipolygon"), ("leisure", "park")])
        walk(&world, 601, (0.6, 1.0), (1.4, 1.0))        // in the park
        walk(&world, 602, (1.7, 1.0), (2.5, 1.0))        // in the housing, beside the park
        let result = try FeatureStoreBuilder().build(from: try world.extract())
        let file = try FeatureStoreFile(data: result.data)
        #expect(try classID(of: 601, in: file) == FeatureClass.path.rawValue, "in the park")
        #expect(try classID(of: 602, in: file) == FeatureClass.pavement.rawValue, "in the housing")
        #expect(result.report.townAreas == 1 && result.report.greenAreas == 1)
    }

    @Test("A built-up area mapped as a relation counts, and its hole does not")
    func townAsRelationWithHole() throws {
        var world = SyntheticWorld()
        world.way(520, world.rectangle(first: 520, 0.3, 0.3, 2.7, 2.7))
        world.way(530, world.rectangle(first: 530, 1.0, 1.0, 2.0, 2.0))
        world.relation(2_000, [(520, "outer", 1), (530, "inner", 1)], [("type", "multipolygon"), ("landuse", "commercial")])
        walk(&world, 611, (0.5, 0.5), (2.5, 0.5))        // in the commercial area
        walk(&world, 612, (1.1, 1.5), (1.9, 1.5))        // in the hole
        let result = try FeatureStoreBuilder().build(from: try world.extract())
        let file = try FeatureStoreFile(data: result.data)
        #expect(try classID(of: 611, in: file) == FeatureClass.pavement.rawValue)
        #expect(try classID(of: 612, in: file) == FeatureClass.path.rawValue, "the hole is outside the area")
    }
}
