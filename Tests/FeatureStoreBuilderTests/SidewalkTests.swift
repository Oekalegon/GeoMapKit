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

    @Test("A footway in a built-up area is pavement; one in a park, or half outside, is a path")
    func inTown() throws {
        var world = SyntheticWorld()
        // Built-up land (residential) with a park in it, a commercial area, a pedestrian area and a station platform.
        let residential = world.rectangle(first: 500, 0.3, 0.9, 2.7, 2.7)
        world.way(500, residential, [("landuse", "residential")])
        let park = world.rectangle(first: 510, 0.4, 1.0, 2.6, 1.6)
        world.way(510, park, [("leisure", "park")])
        let commercial = world.rectangle(first: 520, 0.3, 0.1, 2.7, 0.7)
        world.way(520, commercial, [("landuse", "commercial")])
        let plaza = world.rectangle(first: 530, 0.4, 2.75, 1.8, 2.95)
        world.way(530, plaza, [("highway", "pedestrian"), ("area", "yes")])
        let platform = world.rectangle(first: 540, 2.2, 2.75, 2.6, 2.95)
        world.way(540, platform, [("railway", "platform")])
        func walk(_ id: Int64, _ from: (Double, Double), _ to: (Double, Double), _ extra: [(String, String)] = []) {
            world.node(id * 10, from.0, from.1); world.node(id * 10 + 1, to.0, to.1)
            world.way(id, [id * 10, id * 10 + 1], [("highway", "footway")] + extra)
        }
        walk(601, (0.5, 0.4), (2.5, 0.4))                  // in the commercial area
        walk(602, (0.5, 2.0), (2.5, 2.0))                  // in the residential area, outside the park
        walk(603, (0.5, 1.3), (2.5, 1.3))                  // in the park, which is inside the residential area
        walk(604, (0.5, 2.85), (1.7, 2.85))                // in the pedestrian area
        walk(605, (2.3, 2.85), (2.5, 2.85))                // on the platform
        walk(606, (2.0, 0.55), (2.0, 0.95))                // half of it in built-up areas, half in between
        walk(607, (0.5, 2.72), (2.5, 2.72))                // between the residential area and the plaza, in the open
        walk(608, (0.5, 0.4), (2.5, 0.4), [("sac_scale", "hiking")])      // a trail in the commercial area
        world.node(6090, 0.5, 0.45); world.node(6091, 2.5, 0.45)
        world.way(609, [6090, 6091], [("highway", "path")])                 // not a footway
        let result = try FeatureStoreBuilder().build(from: try world.extract())
        let file = try FeatureStoreFile(data: result.data)
        for id: Int64 in [601, 602, 604, 605] { #expect(try classID(of: id, in: file) == FeatureClass.pavement.rawValue, "way \(id)") }
        for id: Int64 in [603, 606, 607, 608, 609] { #expect(try classID(of: id, in: file) == FeatureClass.path.rawValue, "way \(id)") }
        #expect(result.report.footwaysInTown == 4 && result.report.footwaysBesideRoads == 0)
    }

    @Test("The rule table version is 9")
    func version() { #expect(FeatureClassifier.version == 9) }
}
