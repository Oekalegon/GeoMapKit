import FeatureStore
import Foundation
import GeoCore
import Testing

@testable import FeatureStoreBuilder

@Suite("Sidewalks by geometry")
struct SidewalkTests {
    /// A cell is about 3.3 km wide here, so 0.002 of a cell is about 6.6 m.
    private func build(_ configure: (inout SyntheticWorld) -> Void) throws -> (FeatureStoreFile, BuildReport) {
        var world = SyntheticWorld()
        // A residential road along y = 1.5 from x = 0.3 to 2.7.
        world.node(1, 0.3, 1.5); world.node(2, 2.7, 1.5)
        world.way(100, [1, 2], [("highway", "residential")])
        configure(&world)
        let result = try FeatureStoreBuilder().build(from: try world.extract())
        return (try FeatureStoreFile(data: result.data), result.report)
    }

    private func classID(of id: Int64, in file: FeatureStoreFile) throws -> UInt8? {
        for cell in try file.cells() {
            if let feature = try file.features(in: cell, band: .detail).first(where: { $0.objectID == id && $0.objectType == .way }) {
                return feature.classID
            }
        }
        return nil
    }

    private func footway(_ world: inout SyntheticWorld, id: Int64, from: (Double, Double), to: (Double, Double), _ extra: [(String, String)] = []) {
        world.node(id * 10, from.0, from.1); world.node(id * 10 + 1, to.0, to.1)
        world.way(id, [id * 10, id * 10 + 1], [("highway", "footway")] + extra)
    }

    @Test("A footway that runs beside a road is a sidewalk; one that crosses it, or runs far from it, is a path")
    func besideOrNot() throws {
        let (file, report) = try build { world in
            footway(&world, id: 201, from: (0.5, 1.502), to: (2.5, 1.502))          // 6.6 m north of the road, parallel
            footway(&world, id: 202, from: (1.5, 1.30), to: (1.5, 1.70))            // crosses the road at a right angle
            footway(&world, id: 203, from: (0.5, 1.52), to: (2.5, 1.52))            // 66 m away
            footway(&world, id: 204, from: (1.0, 1.502), to: (1.002, 1.502))        // 6.6 m long: too short to judge
            footway(&world, id: 205, from: (0.5, 1.498), to: (2.5, 1.498))          // the other side of the road
        }
        #expect(try classID(of: 201, in: file) == FeatureClass.pavement.rawValue)
        #expect(try classID(of: 205, in: file) == FeatureClass.pavement.rawValue)
        #expect(try classID(of: 202, in: file) == FeatureClass.path.rawValue, "a crossing is not beside the road")
        #expect(try classID(of: 203, in: file) == FeatureClass.path.rawValue)
        #expect(try classID(of: 204, in: file) == FeatureClass.path.rawValue)
        #expect(report.footwaysBesideRoads == 2)
    }

    @Test("A trail beside a road stays a path, and so does a path that is not a footway")
    func trailsAndPaths() throws {
        let (file, report) = try build { world in
            footway(&world, id: 211, from: (0.5, 1.502), to: (2.5, 1.502), [("sac_scale", "hiking")])
            footway(&world, id: 212, from: (0.5, 1.502), to: (2.5, 1.502), [("trail_visibility", "good")])
            world.node(2130, 0.5, 1.503); world.node(2131, 2.5, 1.503)
            world.way(213, [2130, 2131], [("highway", "path")])
        }
        for id: Int64 in [211, 212, 213] { #expect(try classID(of: id, in: file) == FeatureClass.path.rawValue, "way \(id)") }
        #expect(report.footwaysBesideRoads == 0)
    }

    @Test("Only a road counts: not a pedestrian street, a tunnel, or another footway")
    func onlyRoads() throws {
        var world = SyntheticWorld()
        world.node(1, 0.3, 1.0); world.node(2, 2.7, 1.0)
        world.way(100, [1, 2], [("highway", "pedestrian")])
        world.node(3, 0.3, 2.0); world.node(4, 2.7, 2.0)
        world.way(101, [3, 4], [("highway", "residential"), ("tunnel", "yes")])
        world.node(5, 0.3, 2.5); world.node(6, 2.7, 2.5)
        world.way(102, [5, 6], [("highway", "footway")])
        footway(&world, id: 301, from: (0.5, 1.002), to: (2.5, 1.002))              // beside a pedestrian street
        footway(&world, id: 302, from: (0.5, 2.002), to: (2.5, 2.002))              // above a tunnel
        footway(&world, id: 303, from: (0.5, 2.502), to: (2.5, 2.502))              // beside another footway
        let result = try FeatureStoreBuilder().build(from: try world.extract())
        let file = try FeatureStoreFile(data: result.data)
        for id: Int64 in [301, 302, 303] { #expect(try classID(of: id, in: file) == FeatureClass.path.rawValue, "way \(id)") }
        #expect(result.report.footwaysBesideRoads == 0)
    }

    @Test("A footway that runs beside the road for most of its length is a sidewalk, one that only starts at it is not")
    func share() throws {
        let (file, _) = try build { world in
            // 1.6 of its 2.0 length (80 %) beside the road, then it leaves to the north.
            world.node(2010, 0.5, 1.502); world.node(2011, 1.7, 1.502); world.node(2012, 1.9, 1.7)
            world.way(401, [2010, 2011, 2012], [("highway", "footway")])
            // 0.4 of 2.0 beside the road: a path that starts at the road and leaves it.
            world.node(2020, 0.5, 1.502); world.node(2021, 0.9, 1.502); world.node(2022, 2.5, 1.9)
            world.way(402, [2020, 2021, 2022], [("highway", "footway")])
        }
        #expect(try classID(of: 401, in: file) == FeatureClass.pavement.rawValue)
        #expect(try classID(of: 402, in: file) == FeatureClass.path.rawValue)
    }

    @Test("The rule table version is 8")
    func version() { #expect(FeatureClassifier.version == 8) }
}
