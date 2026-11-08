import FeatureStore
import Foundation
import GeoCore
import Testing

@testable import FeatureStoreBuilder

/// The names of national and state borders, taken from the relations the border ways belong to.
@Suite("Border names")
struct BorderNamesTests {
    private func names(of featureClass: FeatureClass, in world: inout SyntheticWorld) throws -> [String] {
        let result = try FeatureStoreBuilder().build(from: try world.extract())
        let file = try FeatureStoreFile(data: result.data)
        var found: [String] = []
        for cell in try file.cells() {
            for feature in try file.features(in: cell, band: .overview) where feature.classID == featureClass.rawValue {
                found.append(feature.nameID.flatMap { file.string(at: $0) } ?? "")
            }
        }
        return Array(Set(found)).sorted()
    }

    private func border(_ world: inout SyntheticWorld, tags: [(String, String)] = []) {
        world.node(1, 0.5, 1.0); world.node(2, 1.5, 1.0); world.node(3, 2.5, 1.0)
        world.way(10, [1, 2, 3], tags)
    }

    @Test("A national border is named after the two countries, in alphabetical order, and not after the counties")
    func nationalBorder() throws {
        var world = SyntheticWorld()
        border(&world, tags: [("boundary", "administrative"), ("admin_level", "2")])
        world.relation(50, [(10, "outer", 1)], [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "2"), ("name", "Sverige")])
        world.relation(51, [(10, "outer", 1)], [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "2"), ("name", "Norge")])
        world.relation(52, [(10, "outer", 1)], [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "4"), ("name", "Østfold")])
        #expect(try names(of: .countryBorder, in: &world) == ["Norge – Sverige"])
    }

    @Test("A state border is named after the states, not after the country")
    func stateBorder() throws {
        var world = SyntheticWorld()
        border(&world, tags: [("boundary", "administrative"), ("admin_level", "4")])
        world.relation(50, [(10, "outer", 1)], [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "4"), ("name", "Østfold")])
        world.relation(51, [(10, "outer", 1)], [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "4"), ("name", "Akershus")])
        world.relation(52, [(10, "outer", 1)], [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "2"), ("name", "Norge")])
        #expect(try names(of: .boundary, in: &world) == ["Akershus – Østfold"])
    }

    @Test("A border way with a name of its own keeps it")
    func ownName() throws {
        var world = SyntheticWorld()
        border(&world, tags: [("boundary", "administrative"), ("admin_level", "2"), ("name", "Riksgrensen")])
        world.relation(50, [(10, "outer", 1)], [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "2"), ("name", "Norge")])
        #expect(try names(of: .countryBorder, in: &world) == ["Riksgrensen"])
    }

    @Test("A border that is in no relation has no name")
    func noRelation() throws {
        var world = SyntheticWorld()
        border(&world, tags: [("boundary", "administrative"), ("admin_level", "2")])
        #expect(try names(of: .countryBorder, in: &world) == [""])
    }

    @Test("The same name from two relations is written once")
    func repeatedName() throws {
        var world = SyntheticWorld()
        border(&world, tags: [("boundary", "administrative"), ("admin_level", "2")])
        world.relation(50, [(10, "outer", 1)], [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "2"), ("name", "Norge")])
        world.relation(51, [(10, "outer", 1)], [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "2"), ("name", "Norge")])
        #expect(try names(of: .countryBorder, in: &world) == ["Norge"])
    }

    // MARK: Sides

    private let level2: [(String, String)] = [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "2")]

    /// Two regions that share the border way 10, which runs from west to east: `North` above it on the map and `South` below.
    /// Both rings run counter-clockwise, as relations in OSM do for some countries (others run clockwise).
    private func neighbours(_ world: inout SyntheticWorld, wayNodes: [Int64] = [1, 2, 3], north: Bool = true, south: Bool = true) {
        world.node(1, 0.5, 1.0); world.node(2, 1.5, 1.0); world.node(3, 2.5, 1.0)
        world.node(4, 2.5, 0.5); world.node(5, 0.5, 0.5)
        world.node(7, 0.5, 1.5); world.node(8, 2.5, 1.5)
        world.way(10, wayNodes, level2)
        world.way(11, [3, 4, 5]); world.way(12, [5, 1])
        world.way(13, [1, 7, 8]); world.way(14, [8, 3])
        if north {
            world.relation(50, [(10, "outer", 1), (11, "outer", 1), (12, "outer", 1)], level2 + [("name", "North")])
        }
        if south {
            world.relation(51, [(10, "outer", 1), (13, "outer", 1), (14, "outer", 1)], level2 + [("name", "South")])
        }
    }

    @Test("Each region is named on its side of the border way, left and right of the way's direction")
    func sides() throws {
        var world = SyntheticWorld()
        neighbours(&world)
        #expect(try names(of: .countryBorder, in: &world) == ["North\nSouth"])
    }

    @Test("A way stored the other way round swaps the sides")
    func reversedWay() throws {
        var world = SyntheticWorld()
        neighbours(&world, wayNodes: [3, 2, 1])
        // The rings now do not close at the nodes of way 10 in the order the ways are given, but the nodes are the same.
        #expect(try names(of: .countryBorder, in: &world) == ["South\nNorth"])
    }

    @Test("A region whose ring cannot be followed takes the side that is free")
    func unknownSide() throws {
        var world = SyntheticWorld()
        // The southern region is only a name on this way: no ring to follow.
        neighbours(&world, south: false)
        world.relation(51, [(10, "outer", 1)], level2 + [("name", "South")])
        #expect(try names(of: .countryBorder, in: &world) == ["North\nSouth"])
    }

    @Test("A region on one side only is named on that side alone")
    func oneSide() throws {
        var world = SyntheticWorld()
        neighbours(&world, south: false)
        #expect(try names(of: .countryBorder, in: &world) == ["North\n"])
    }

    @Test("A ring clockwise on the map has its region on the right")
    func clockwise() {
        func ring(_ points: [(Double, Double)]) -> [Coordinate] { points.map { Coordinate(latitude: $0.0, longitude: $0.1) } }
        let north = ring([(0, 0), (1, 0), (1, 1), (0, 1)])
        #expect(BoundarySides.isClockwise(north) == true, "north, east, south, west")
        #expect(BoundarySides.isClockwise(north.reversed()) == false)
        #expect(BoundarySides.isClockwise(ring([(0, 0), (1, 1)])) == nil, "no area")
        #expect(BoundarySides.isClockwise(ring([(0, 0), (1, 1), (2, 2)])) == nil, "a straight line has none")
        // Across the antimeridian the longitudes jump from 179 to -179.
        #expect(BoundarySides.isClockwise(ring([(0, 179), (1, 179), (1, -179), (0, -179)])) == true)
    }

    @Test("The limit of the territorial waters is no border, unless two countries share it")
    func seaLimit() throws {
        let limit = level2 + [("maritime", "yes"), ("border_type", "territorial")]
        var shared = SyntheticWorld()
        shared.node(1, 0.5, 1.0); shared.node(2, 1.5, 1.0)
        shared.way(10, [1, 2], limit)
        shared.relation(50, [(10, "outer", 1)], level2 + [("name", "Norge")])
        shared.relation(51, [(10, "outer", 1)], level2 + [("name", "Sverige")])
        #expect(try names(of: .countryBorder, in: &shared) == ["Norge – Sverige"], "the line between two countries is drawn")
        var alone = SyntheticWorld()
        alone.node(1, 0.5, 1.0); alone.node(2, 1.5, 1.0)
        alone.way(10, [1, 2], limit)
        alone.relation(50, [(10, "outer", 1)], level2 + [("name", "Norge")])
        #expect(try names(of: .countryBorder, in: &alone) == [], "the limit of one country's waters is not")
    }
}
