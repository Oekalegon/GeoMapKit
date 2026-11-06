import Foundation
import Testing
import GeoCore
@testable import OSMPBF

/// A world with an area of interest (the box below) and objects around it:
///
/// - way 100 crosses the edge (node 1 inside, node 4 outside)
/// - way 101 is far away and unrelated
/// - way 102 is far away but is a member of relation 200, which touches the box
/// - way 103 is inside; way 104 is far away and a member of relation 203 only
/// - relation 202 has relation 200 as its only member (a relation of a relation)
/// - node 3 is an untagged orphan inside the box and must be dropped
private enum World {
    static let box = BoundingBox(south: 47, west: 9, north: 48, east: 10)

    private static func raw(_ degrees: Double) -> Int64 { Int64((degrees * 1e7).rounded()) }

    static func file(extraWays: [Data] = []) -> Data {
        var builder = PBFFileBuilder()
        builder.appendBlob(type: "OSMHeader", payload: PBFFileBuilder.headerPayload(optional: ["Sort.Type_then_ID"]))

        let positions: [(id: Int64, lat: Double, lon: Double)] = [
            (1, 47.5, 9.5), (2, 47.6, 9.6), (3, 47.7, 9.7), (4, 46.5, 9.5),
            (5, 40.0, 5.0), (6, 40.1, 5.1), (7, 39.0, 4.0), (8, 39.1, 4.1),
            (9, 47.2, 9.2), (10, 41.0, 6.0), (11, 38.0, 3.0), (12, 38.1, 3.1),
        ]
        let nodeStrings = ["", "amenity", "cafe", "place", "village"]
        let tags: [[(key: Int32, value: Int32)]] = positions.map { position in
            switch position.id {
            case 2: [(1, 2)]
            case 10: [(3, 4)]
            default: []
            }
        }
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(
            strings: nodeStrings,
            dense: PBFFileBuilder.denseNodes(
                ids: positions.map(\.id), latitudes: positions.map { raw($0.lat) },
                longitudes: positions.map { raw($0.lon) }, tags: tags
            )
        ))

        let wayStrings = ["", "highway", "path"]
        let path = [(key: UInt64(1), value: UInt64(2))]
        let ways = [
            PBFFileBuilder.way(id: 100, nodeIDs: [1, 4], tags: path),
            PBFFileBuilder.way(id: 101, nodeIDs: [5, 6], tags: path),
            PBFFileBuilder.way(id: 102, nodeIDs: [7, 8], tags: path),
            PBFFileBuilder.way(id: 103, nodeIDs: [9, 4], tags: path),
            PBFFileBuilder.way(id: 104, nodeIDs: [11, 12], tags: path),
        ] + extraWays
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(strings: wayStrings, ways: ways))

        let relationStrings = ["", "type", "multipolygon", "route_master", "outer", "inner", "label"]
        let multipolygon = [(key: UInt64(1), value: UInt64(2))]
        let relations = [
            PBFFileBuilder.relation(id: 200, members: [(id: 100, role: 4, type: 1), (id: 102, role: 5, type: 1), (id: 10, role: 6, type: 0)], tags: multipolygon),
            PBFFileBuilder.relation(id: 201, members: [(id: 101, role: 4, type: 1)], tags: multipolygon),
            PBFFileBuilder.relation(id: 202, members: [(id: 200, role: 0, type: 2)], tags: [(key: 1, value: 3)]),
            PBFFileBuilder.relation(id: 203, members: [(id: 100, role: 0, type: 1), (id: 103, role: 0, type: 1), (id: 104, role: 0, type: 1)], tags: multipolygon),
        ]
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(strings: relationStrings, relations: relations))
        return builder.file
    }
}

@Suite("AreaCutter")
struct AreaCutterTests {
    private func cut(_ data: Data = World.file(), options: AreaCutter.Options = .init(), box: BoundingBox = World.box) throws -> OSMExtract {
        try AreaCutter(options: options).cut(PBFReader(data: data), to: box)
    }

    @Test("Keeps ways that touch the box whole, with their nodes outside the box")
    func keepsEdgeCrossingWaysWhole() throws {
        let extract = try cut()
        let crossing = try #require(extract.ways.first { $0.id == 100 })
        #expect(crossing.nodeIDs == [1, 4])
        // Node 4 lies outside the box but must be present so the way is complete.
        let outsideNode = try #require(extract.node(withID: 4))
        #expect(!World.box.contains(outsideNode.coordinate))
        #expect(extract.missingNodeCount == 0)
    }

    @Test("Drops ways that do not touch the box or any relation that does")
    func dropsUnrelatedWays() throws {
        let extract = try cut()
        #expect(extract.ways.map(\.id) == [100, 102, 103, 104])   // 101 is unrelated
        #expect(extract.node(withID: 5) == nil)
        #expect(extract.node(withID: 6) == nil)
    }

    @Test("Completes relations that touch the box with far-away member ways and nodes")
    func completesRelations() throws {
        let extract = try cut()
        // Way 102 and nodes 7, 8 (the way) and 10 (a node member) are far from the box.
        #expect(extract.ways.contains { $0.id == 102 })
        #expect(extract.node(withID: 7) != nil)
        #expect(extract.node(withID: 8) != nil)
        #expect(extract.node(withID: 10)?.tags == ["place": "village"])
        let relation = try #require(extract.relations.first { $0.relation.id == 200 })
        #expect(relation.isComplete)
        #expect(relation.relation.members.count == 3)
    }

    @Test("Selects relations that contain a selected relation")
    func selectsParentRelations() throws {
        let extract = try cut()
        #expect(extract.relations.map(\.relation.id) == [200, 202, 203])   // 201 does not touch
        let parent = try #require(extract.relations.first { $0.relation.id == 202 })
        #expect(parent.isComplete)
    }

    @Test("Keeps tagged nodes inside the box and drops untagged orphans")
    func nodeSelection() throws {
        let extract = try cut()
        #expect(extract.node(withID: 2)?.tags == ["amenity": "cafe"])   // tagged, on no way
        #expect(extract.node(withID: 3) == nil)                         // untagged orphan
        #expect(extract.nodes.map(\.id) == [1, 2, 4, 7, 8, 9, 10, 11, 12])
        #expect(extract.nodes.map(\.id) == extract.nodes.map(\.id).sorted())
    }

    @Test("Coordinates of kept nodes are exact")
    func coordinates() throws {
        let extract = try cut()
        #expect(extract.node(withID: 1)?.coordinate == Coordinate(latitude: 47.5, longitude: 9.5))
        #expect(extract.node(withID: 4)?.coordinate == Coordinate(latitude: 46.5, longitude: 9.5))
    }

    @Test("A relation above the member limit is kept but not completed and marked incomplete")
    func relationLimit() throws {
        let extract = try cut(options: .init(relationMemberLimit: 2))
        // Relation 203 has three way members; way 104 would only come from completing it.
        #expect(extract.ways.map(\.id) == [100, 102, 103])
        #expect(extract.node(withID: 11) == nil)
        let big = try #require(extract.relations.first { $0.relation.id == 203 })
        #expect(!big.isComplete)
        #expect(big.relation.members.count == 3)      // the member list itself is never trimmed
        let small = try #require(extract.relations.first { $0.relation.id == 200 })
        #expect(small.isComplete)
    }

    @Test("A box with nothing in it gives an empty extract")
    func emptyBox() throws {
        let extract = try cut(box: BoundingBox(south: 0, west: 0, north: 1, east: 1))
        #expect(extract.nodes.isEmpty)
        #expect(extract.ways.isEmpty)
        #expect(extract.relations.isEmpty)
    }

    @Test("An invalid box is rejected")
    func invalidBox() {
        #expect(throws: AreaCutterError.invalidBoundingBox) {
            try self.cut(box: BoundingBox(south: 48, west: 9, north: 47, east: 10))
        }
        #expect(throws: AreaCutterError.invalidBoundingBox) {
            try self.cut(box: BoundingBox(south: .nan, west: 9, north: 47, east: 10))
        }
    }

    @Test("Nodes that a way refers to but the file lacks are counted, not fatal")
    func missingNodes() throws {
        let broken = PBFFileBuilder.way(id: 105, nodeIDs: [1, 999], tags: [(key: 1, value: 2)])
        let extract = try cut(World.file(extraWays: [broken]))
        #expect(extract.missingNodeCount == 1)
        #expect(extract.ways.contains { $0.id == 105 })
    }

    @Test("The header of the source file is carried over")
    func header() throws {
        let extract = try cut()
        #expect(extract.header.optionalFeatures == ["Sort.Type_then_ID"])
        #expect(extract.boundingBox == World.box)
    }
}

@Suite("Selective decoding")
struct SelectiveDecodingTests {
    @Test("Only the requested kinds are decoded")
    func kinds() throws {
        let reader = PBFReader(data: World.file())
        var counts: [OSMObjectKinds: (nodes: Int, ways: Int, relations: Int)] = [:]
        for kinds in [OSMObjectKinds.nodes, .ways, .relations, .all] {
            var count = (nodes: 0, ways: 0, relations: 0)
            try reader.forEachBlock(kinds: kinds) { block in
                count.nodes += block.nodes.count
                count.ways += block.ways.count
                count.relations += block.relations.count
            }
            counts[kinds] = count
        }
        #expect(counts[.nodes]! == (12, 0, 0))
        #expect(counts[.ways]! == (0, 5, 0))
        #expect(counts[.relations]! == (0, 0, 4))
        #expect(counts[.all]! == (12, 5, 4))
    }
}
