import FeatureStore
import Foundation
import GeoCore
import OSMPBF
import PBFTestSupport

@testable import FeatureStoreBuilder

/// A small hand-made world on a 3 by 3 block of cells, written as a PBF file.
///
/// Positions are given as fractions of the block (0 to 3 across), see `Block`. The cut box reaches half a
/// cell beyond the block, so the block's nine cells are the cells that lie fully inside it.
struct SyntheticWorld {
    let block = Block()
    private var strings: [String] = [""]
    private var nodeSpecs: [(id: Int64, x: Double, y: Double, tags: [(String, String)])] = []
    private var waySpecs: [(id: Int64, nodes: [Int64], tags: [(String, String)])] = []
    private var relationSpecs: [(id: Int64, members: [(id: Int64, role: String, type: UInt64)], tags: [(String, String)])] = []

    static let precomposed = "caf\u{00E9}"
    static let decomposed = "cafe\u{0301}"

    /// The cut area: the block plus half a cell on every side.
    var box: BoundingBox {
        let northWest = block.point(-0.5, -0.5), southEast = block.point(3.5, 3.5)
        return BoundingBox(
            south: Double(southEast.latitude) / 1e7, west: Double(northWest.longitude) / 1e7,
            north: Double(northWest.latitude) / 1e7, east: Double(southEast.longitude) / 1e7)
    }

    private mutating func index(_ string: String) -> Int32 {
        if let existing = strings.firstIndex(where: { $0.utf8.elementsEqual(string.utf8) }) { return Int32(existing) }
        strings.append(string)
        return Int32(strings.count - 1)
    }

    mutating func node(_ id: Int64, _ x: Double, _ y: Double, _ tags: [(String, String)] = []) {
        nodeSpecs.append((id, x, y, tags))
    }

    mutating func way(_ id: Int64, _ nodes: [Int64], _ tags: [(String, String)] = []) {
        waySpecs.append((id, nodes, tags))
    }

    mutating func relation(_ id: Int64, _ members: [(id: Int64, role: String, type: UInt64)], _ tags: [(String, String)]) {
        relationSpecs.append((id, members, tags))
    }

    /// Adds a closed rectangle of four nodes (ids `first` to `first + 3`) and returns the closed node list.
    mutating func rectangle(first: Int64, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [Int64] {
        node(first, x0, y0); node(first + 1, x1, y0); node(first + 2, x1, y1); node(first + 3, x0, y1)
        return [first, first + 1, first + 2, first + 3, first]
    }

    /// The world used by the end-to-end tests.
    static func standard() -> SyntheticWorld {
        var world = SyntheticWorld()
        world.node(1, 1.5, 1.5, [("natural", "peak"), ("name", "Test Peak")])
        world.node(2, 0.5, 0.5, [("amenity", "drinking_water")])
        world.node(3, 2.5, 0.5, [(precomposed, "v1"), (decomposed, "v2")])
        world.node(4, -0.2, 1.5, [("amenity", "drinking_water")])       // outside the written cells
        world.node(5, 1.5, 0.4, [("amenity", "restaurant"), ("name", "Zum Test")])

        // A path across two cell borders, and one that leaves the written cells.
        for (offset, position) in [(0.3, 1.5), (0.9, 1.55), (1.4, 1.45), (1.95, 1.5), (2.7, 1.5)].enumerated() {
            world.node(10 + Int64(offset), position.0, position.1)
        }
        world.way(100, [10, 11, 12, 13, 14], [("highway", "path"), ("name", "Rheinweg"), ("sac_scale", "hiking")])
        world.node(15, 2.5, 2.5); world.node(16, 3.3, 2.5)
        world.way(101, [15, 16], [("highway", "path")])

        // A forest that crosses a border.
        let forest = world.rectangle(first: 20, 0.4, 0.15, 1.6, 0.45)
        world.way(200, forest, [("landuse", "forest")])

        // A lake with a hole (untagged member ways; the tags are on the relation).
        let shore = world.rectangle(first: 30, 0.2, 2.1, 2.8, 2.8)
        let hole = world.rectangle(first: 34, 1.2, 2.3, 1.8, 2.6)
        world.way(301, shore); world.way(302, hole)
        world.relation(300, [(301, "outer", 1), (302, "inner", 1)], [("type", "multipolygon"), ("natural", "water"), ("name", "Lake")])

        // A multipolygon whose ring does not close, and one with a member way missing from the file.
        world.node(40, 0.3, 0.7); world.node(41, 0.9, 0.8); world.node(42, 0.9, 1.0)
        world.way(401, [40, 41, 42])
        world.relation(400, [(401, "outer", 1)], [("type", "multipolygon"), ("landuse", "meadow")])
        world.node(43, 2.2, 0.7); world.node(44, 2.6, 0.8)
        world.way(451, [43, 44])
        world.relation(450, [(451, "outer", 1), (452, "outer", 1)], [("type", "multipolygon"), ("natural", "scrub")])

        // Old style: the tags are on the single outer way, the relation has only a type.
        let field = world.rectangle(first: 50, 2.1, 0.05, 2.4, 0.35)
        world.way(501, field, [("landuse", "farmland")])
        world.relation(500, [(501, "outer", 1)], [("type", "multipolygon")])

        // A route relation is only stored in the relation table.
        world.relation(600, [(100, "", 1), (1, "stop", 0)], [("type", "route"), ("route", "hiking"), ("name", "Test Route")])

        // An untagged way in no relation, a way with a node missing from the file, and a building.
        world.node(60, 2.0, 1.2); world.node(61, 2.5, 1.25)
        world.way(700, [60, 61])
        world.node(62, 0.3, 0.2); world.node(63, 0.5, 0.25); world.node(64, 0.7, 0.3); world.node(65, 0.9, 0.2)
        world.way(800, [62, 63, 999, 64, 65], [("highway", "track"), ("tracktype", "grade2")])
        // Landmarks (rule table version 2): a power line, a ski piste and a tree.
        world.node(80, 1.1, 0.9); world.node(81, 1.9, 0.95)
        world.way(1000, [80, 81], [("power", "line")])
        world.node(82, 0.2, 1.8); world.node(83, 0.8, 1.9)
        world.way(1001, [82, 83], [("piste:type", "nordic"), ("piste:difficulty", "easy")])
        world.node(6, 0.8, 0.8, [("natural", "tree")])
        let house = world.rectangle(first: 70, 1.1, 1.1, 1.2, 1.2)
        world.way(900, house, [("building", "yes")])
        return world
    }

    /// The PBF file.
    mutating func file() -> Data {
        var builder = PBFFileBuilder()
        builder.appendBlob(type: "OSMHeader", payload: PBFFileBuilder.headerPayload())
        let sortedNodes = nodeSpecs.sorted { $0.id < $1.id }
        let tagIndices = sortedNodes.map { spec in spec.tags.map { (key: index($0.0), value: index($0.1)) } }
        let wayData = waySpecs.sorted { $0.id < $1.id }.map { spec in
            PBFFileBuilder.way(
                id: spec.id, nodeIDs: spec.nodes,
                tags: spec.tags.map { (key: UInt64(index($0.0)), value: UInt64(index($0.1))) })
        }
        let relationData = relationSpecs.sorted { $0.id < $1.id }.map { spec in
            PBFFileBuilder.relation(
                id: spec.id,
                members: spec.members.map { (id: $0.id, role: index($0.role), type: $0.type) },
                tags: spec.tags.map { (key: UInt64(index($0.0)), value: UInt64(index($0.1))) })
        }
        let dense = PBFFileBuilder.denseNodes(
            ids: sortedNodes.map(\.id),
            latitudes: sortedNodes.map { Int64(block.point($0.x, $0.y).latitude) },
            longitudes: sortedNodes.map { Int64(block.point($0.x, $0.y).longitude) },
            tags: tagIndices)
        builder.appendBlob(
            type: "OSMData", payload: PBFFileBuilder.primitiveBlock(strings: strings, dense: dense, ways: wayData, relations: relationData))
        return builder.file
    }

    /// Cuts the world to its box.
    mutating func extract() throws -> OSMExtract {
        try AreaCutter().cut(try PBFReader(data: file()), to: box)
    }
}
