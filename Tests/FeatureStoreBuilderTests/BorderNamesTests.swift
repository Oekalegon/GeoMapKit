import FeatureStore
import Foundation
import GeoCore
import OSMPBF
import Testing

@testable import FeatureStoreBuilder

/// The names of national and state borders, taken from the relations the border ways belong to.
@Suite("Border names")
struct BorderNamesTests {
    private func names(of featureClass: FeatureClass, ofWay way: Int64? = nil, in world: inout SyntheticWorld) throws -> [String] {
        let result = try FeatureStoreBuilder().build(from: try world.extract())
        let file = try FeatureStoreFile(data: result.data)
        var found: [String] = []
        for cell in try file.cells() {
            for feature in try file.features(in: cell, band: .overview) where feature.classID == featureClass.rawValue && (way == nil || feature.objectID == way) {
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

    // MARK: Ways with no border tags

    private func count(of featureClass: FeatureClass, in world: inout SyntheticWorld) throws -> Int {
        let result = try FeatureStoreBuilder().build(from: try world.extract())
        let file = try FeatureStoreFile(data: result.data)
        var found = 0
        for cell in try file.cells() {
            for feature in try file.features(in: cell, band: .overview) where feature.classID == featureClass.rawValue { found += 1 }
        }
        return found
    }

    private func countInDetail(of featureClass: FeatureClass, in world: inout SyntheticWorld) throws -> Int {
        let file = try FeatureStoreFile(data: try FeatureStoreBuilder().build(from: try world.extract()).data)
        var found = 0
        for cell in try file.cells() {
            for feature in try file.features(in: cell, band: .detail) where feature.classID == featureClass.rawValue { found += 1 }
        }
        return found
    }

    @Test("A way with no border tags that belongs to a national border relation is a national border")
    func untaggedWayInCountryRelation() throws {
        var world = SyntheticWorld()
        border(&world, tags: [("source", "Landsat")])
        world.relation(50, [(10, "outer", 1)], [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "2"), ("name", "Suomi")])
        world.relation(51, [(10, "outer", 1)], [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "2"), ("name", "Россия")])
        #expect(try count(of: .countryBorder, in: &world) > 0)
        #expect(try names(of: .countryBorder, in: &world) == ["Suomi – Россия"])
    }

    @Test("A way tagged boundary=administrative with no admin_level takes its class from the relation, one with another level does not")
    func administrativeWayWithoutLevel() throws {
        var world = SyntheticWorld()
        border(&world, tags: [("boundary", "administrative"), ("source", "Landsat")])
        for (offset, tags) in borderRelations.enumerated() { world.relation(Int64(50 + offset), [(10, "outer", 1)], tags) }
        #expect(try count(of: .countryBorder, in: &world) > 0)
        var municipality = SyntheticWorld()
        border(&municipality, tags: [("boundary", "administrative"), ("admin_level", "8")])
        for (offset, tags) in borderRelations.enumerated() { municipality.relation(Int64(50 + offset), [(10, "outer", 1)], tags) }
        #expect(try count(of: .countryBorder, in: &municipality) == 0)
    }

    @Test("A border way that is also a stream or a fence is a border as well as that; a municipal border way is not")
    func borderBesideOwnClass() throws {
        for own in [("waterway", "stream"), ("barrier", "fence")] {
            var world = SyntheticWorld()
            border(&world, tags: [("boundary", "administrative"), ("admin_level", "2"), own])
            #expect(try count(of: .countryBorder, in: &world) > 0, "\(own.0) keeps its class and gains the border")
            if own.0 == "waterway" { #expect(try countInDetail(of: .waterLine, in: &world) > 0, "the stream is still a stream") }
        }
        var state = SyntheticWorld()
        border(&state, tags: [("boundary", "administrative"), ("admin_level", "4"), ("waterway", "river")])
        #expect(try count(of: .boundary, in: &state) > 0)
        var municipality = SyntheticWorld()
        border(&municipality, tags: [("boundary", "administrative"), ("admin_level", "8"), ("waterway", "river")])
        #expect(try count(of: .countryBorder, in: &municipality) == 0 && (try count(of: .boundary, in: &municipality)) == 0)
        var sea = SyntheticWorld()
        border(&sea, tags: [("boundary", "administrative"), ("admin_level", "2"), ("border_type", "territorial"), ("waterway", "river")])
        #expect(try count(of: .countryBorder, in: &sea) == 0, "the limit of the territorial waters is no border")
    }

    @Test("A stream or a road that is a member of a national border relation is a border as well, with no border tag of its own")
    func memberOfBorderRelationWithOwnClass() throws {
        for own in [("waterway", "river"), ("highway", "track")] {
            var world = SyntheticWorld()
            border(&world, tags: [own, ("name", "Cor")])
            for (offset, tags) in borderRelations.enumerated() { world.relation(Int64(50 + offset), [(10, "outer", 1)], tags) }
            #expect(try count(of: .countryBorder, in: &world) > 0, "\(own.1) in the border relations")
        }
        var alone = SyntheticWorld()
        border(&alone, tags: [("waterway", "river")])
        #expect(try count(of: .countryBorder, in: &alone) == 0, "no relation, no border")
        var sea = SyntheticWorld()
        border(&sea, tags: [("waterway", "river"), ("boundary", "administrative"), ("admin_level", "2"), ("border_type", "territorial")])
        sea.relation(50, [(10, "outer", 1)], borderRelations[0])
        #expect(try count(of: .countryBorder, in: &sea) == 0, "the limit of the territorial waters is no border")
    }

    @Test("A forest that is a nature reserve gets the border of the reserve, and a track with a piste gets the piste")
    func overlays() throws {
        let classifier = FeatureClassifier()
        let forest = ClassifierTagArray([OSMTag(key: "landuse", value: "forest"), OSMTag(key: "leisure", value: "nature_reserve")])
        let primary = classifier.classify(forest, shape: .closedWay).featureClass
        #expect(primary != .parkBorder)
        #expect(classifier.overlays(forest, primary: primary).map(\.featureClass) == [.parkBorder])
        let track = ClassifierTagArray([OSMTag(key: "highway", value: "track"), OSMTag(key: "piste:type", value: "nordic")])
        #expect(classifier.overlays(track, primary: classifier.classify(track, shape: .openWay).featureClass).map(\.featureClass) == [.piste])
        let shop = ClassifierTagArray([OSMTag(key: "building", value: "retail"), OSMTag(key: "shop", value: "supermarket"), OSMTag(key: "addr:street", value: "X")])
        #expect(classifier.overlays(shop, primary: .building).isEmpty, "a shop in a building is no overlay")
        let plain = ClassifierTagArray([OSMTag(key: "boundary", value: "administrative"), OSMTag(key: "admin_level", value: "2")])
        #expect(classifier.overlays(plain, primary: .countryBorder).isEmpty, "never the primary class again")
    }

    @Test("A closed way that is a forest and a nature reserve is stored as the forest and as the border of the reserve")
    func forestReserveWay() throws {
        var world = SyntheticWorld()
        world.way(100, world.rectangle(first: 10, 0.5, 0.5, 2.5, 2.5), [("landuse", "forest"), ("leisure", "nature_reserve"), ("name", "Skov")])
        #expect(try count(of: .forest, in: &world) > 0)
        #expect(try count(of: .parkBorder, in: &world) > 0)
    }

    @Test("A way with no border tags that belongs to a state border relation is a state border")
    func untaggedWayInStateRelation() throws {
        var world = SyntheticWorld()
        border(&world, tags: [("source", "Landsat")])
        world.relation(50, [(10, "outer", 1)], [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "4"), ("name", "Østfold")])
        #expect(try count(of: .boundary, in: &world) > 0)
        #expect(try count(of: .countryBorder, in: &world) == 0)
    }

    @Test("A way in no border relation stays what it was")
    func otherWaysKeepTheirClass() throws {
        var world = SyntheticWorld()
        border(&world, tags: [("source", "Landsat")])
        #expect(try count(of: .countryBorder, in: &world) == 0)
        var roadWorld = SyntheticWorld()
        border(&roadWorld, tags: [("highway", "track")])
        #expect(try count(of: .countryBorder, in: &roadWorld) == 0)
    }

    private let borderRelations: [[(String, String)]] = [
        [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "2"), ("name", "Suomi")],
        [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "2"), ("name", "Россия")],
    ]

    @Test("An untagged way of a national border stays a border when an area relation has it as a member too")
    func untaggedBorderWayInAreaRelation() throws {
        // The Nordic countries as one multipolygon, and a nature reserve whose outline runs along the border.
        for area in [[("type", "multipolygon"), ("name", "Norden")], [("type", "boundary"), ("boundary", "protected_area"), ("name", "Pasvik")]] {
            var world = SyntheticWorld()
            border(&world)
            for (offset, tags) in borderRelations.enumerated() { world.relation(Int64(50 + offset), [(10, "outer", 1)], tags) }
            world.relation(60, [(10, "outer", 1)], area)
            #expect(try count(of: .countryBorder, in: &world) > 0)
        }
    }

    @Test("An untagged way in an area relation only is still part of the area, and no border")
    func untaggedWayInAreaRelationOnly() throws {
        var world = SyntheticWorld()
        border(&world)
        world.relation(60, [(10, "outer", 1)], [("type", "multipolygon"), ("name", "Norden")])
        #expect(try count(of: .countryBorder, in: &world) == 0)
        #expect(try count(of: .other, in: &world) == 0)
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
        // The other sides of the rings are tracks, so that only way 10 is a border here (a way with no class of its own that
        // belongs to a border relation would be one too, see below).
        let track = [("highway", "track")]
        world.way(11, [3, 4, 5], track); world.way(12, [5, 1], track)
        world.way(13, [1, 7, 8], track); world.way(14, [8, 3], track)
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
        #expect(try names(of: .countryBorder, ofWay: 10, in: &world) == ["North\nSouth"])
    }

    @Test("A way stored the other way round swaps the sides")
    func reversedWay() throws {
        var world = SyntheticWorld()
        neighbours(&world, wayNodes: [3, 2, 1])
        // The rings now do not close at the nodes of way 10 in the order the ways are given, but the nodes are the same.
        #expect(try names(of: .countryBorder, ofWay: 10, in: &world) == ["South\nNorth"])
    }

    @Test("A region whose ring cannot be followed takes the side that is free")
    func unknownSide() throws {
        var world = SyntheticWorld()
        // The southern region is only a name on this way: no ring to follow.
        neighbours(&world, south: false)
        world.relation(51, [(10, "outer", 1)], level2 + [("name", "South")])
        #expect(try names(of: .countryBorder, ofWay: 10, in: &world) == ["North\nSouth"])
    }

    @Test("A region on one side only is named on that side alone")
    func oneSide() throws {
        var world = SyntheticWorld()
        neighbours(&world, south: false)
        #expect(try names(of: .countryBorder, ofWay: 10, in: &world) == ["North\n"])
    }

    @Test("A relation with too many ways missing from the extract is not followed: the names are in alphabetical order")
    func tooManyMissing() throws {
        var world = SyntheticWorld()
        neighbours(&world, north: false, south: false)
        // One of the four ways of each relation is not in the extract: 25%, far over the limit.
        world.relation(50, [(10, "outer", 1), (11, "outer", 1), (12, "outer", 1), (99, "outer", 1)], level2 + [("name", "North")])
        world.relation(51, [(10, "outer", 1), (13, "outer", 1), (14, "outer", 1), (98, "outer", 1)], level2 + [("name", "South")])
        #expect(try names(of: .countryBorder, ofWay: 10, in: &world) == ["North – South"])
    }

    @Test("A relation whose ways do not join up is not followed")
    func notJoined() throws {
        var world = SyntheticWorld()
        neighbours(&world, north: false, south: false)
        // The other ways lie apart from way 10, so no direction of travel can be found.
        world.node(20, 5.5, 5.0); world.node(21, 5.6, 5.0); world.node(22, 6.5, 6.0); world.node(23, 6.6, 6.0)
        world.way(30, [20, 21]); world.way(31, [22, 23])
        world.relation(50, [(30, "outer", 1), (10, "outer", 1), (31, "outer", 1)], level2 + [("name", "North")])
        world.relation(51, [(31, "outer", 1), (10, "outer", 1), (30, "outer", 1)], level2 + [("name", "South")])
        #expect(try names(of: .countryBorder, ofWay: 10, in: &world) == ["North – South"])
    }

    @Test("The stored border keeps the direction of its way, which the sides are given in")
    func directionKept() throws {
        var world = SyntheticWorld()
        neighbours(&world)
        let result = try FeatureStoreBuilder().build(from: try world.extract())
        let file = try FeatureStoreFile(data: result.data)
        var pieces = 0
        for cell in try file.cells() {
            for feature in try file.features(in: cell, band: .overview) where feature.classID == FeatureClass.countryBorder.rawValue && feature.objectID == 10 {
                for part in feature.parts {
                    pieces += 1
                    #expect(zip(part.points, part.points.dropFirst()).allSatisfy { $0.0.longitude <= $0.1.longitude }, "west to east, as the way")
                }
            }
        }
        #expect(pieces > 0)
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
