import Foundation
import Testing
import GeoCore
import PBFTestSupport
@testable import OSMPBF

/// A world with an area of interest (the box below) and objects around it:
///
/// - way 100 crosses the edge (node 1 inside, node 4 outside)
/// - way 101 is far away and unrelated
/// - way 102 is far away but is a member of relation 200, which touches the box
/// - way 103 is inside; way 104 is far away and a member of relation 203 only
/// - relation 202 has relation 200 as its only member (a relation of a relation); 205 has 202
///   and is listed before it in the file, so selecting it takes a second round
/// - relation 204 touches the box only through node member 2
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
            PBFFileBuilder.relation(id: 205, members: [(id: 202, role: 0, type: 2)], tags: [(key: 1, value: 3)]),
            PBFFileBuilder.relation(id: 204, members: [(id: 2, role: 0, type: 0)], tags: multipolygon),
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
        #expect(extract.relations.map(\.relation.id) == [200, 202, 203, 204, 205])   // 201 does not touch
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

    @Test("A relation is selected through a node member inside the box")
    func selectedThroughNodeMember() throws {
        let extract = try cut()
        let relation = try #require(extract.relations.first { $0.relation.id == 204 })
        #expect(relation.isComplete)
    }

    @Test("Relations of relations are followed more than one level, whatever the file order")
    func nestedRelationsTwoLevels() throws {
        let extract = try cut()
        #expect(extract.relations.contains { $0.relation.id == 205 })
    }

    @Test("A limit of zero completes nothing, and a negative limit behaves like zero")
    func zeroLimit() throws {
        for limit in [0, -5] {
            let extract = try cut(options: .init(relationMemberLimit: limit))
            #expect(extract.ways.map(\.id) == [100, 103])       // only ways touching the box
            let relation = try #require(extract.relations.first { $0.relation.id == 200 })
            #expect(!relation.isComplete)                        // way 102 was not fetched
        }
    }

    @Test("The edges of the box are inclusive")
    func inclusiveEdges() throws {
        // A degenerate box exactly on node 1 (47.5, 9.5).
        let extract = try cut(box: BoundingBox(south: 47.5, west: 9.5, north: 47.5, east: 9.5))
        #expect(extract.node(withID: 1) != nil)
        #expect(extract.ways.contains { $0.id == 100 })
    }

    @Test("KNOWN LIMITATION: a way with no vertex inside the box is not selected, even if it covers or crosses it")
    func wayWithoutVertexInsideIsMissed() throws {
        func raw(_ degrees: Double) -> Int64 { Int64((degrees * 1e7).rounded()) }
        var builder = PBFFileBuilder()
        builder.appendBlob(type: "OSMHeader", payload: PBFFileBuilder.headerPayload())
        // A square lake much larger than the box (all vertices outside), and a straight road crossing it.
        let points: [(Int64, Double, Double)] = [(1, 40, 0), (2, 40, 20), (3, 60, 20), (4, 60, 0), (5, 47.5, -5), (6, 47.5, 15)]
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(
            strings: [""],
            dense: PBFFileBuilder.denseNodes(
                ids: points.map(\.0), latitudes: points.map { raw($0.1) }, longitudes: points.map { raw($0.2) }
            )
        ))
        let tags = [(key: UInt64(1), value: UInt64(2))]
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(strings: ["", "natural", "water"], ways: [
            PBFFileBuilder.way(id: 10, nodeIDs: [1, 2, 3, 4, 1], tags: tags),
            PBFFileBuilder.way(id: 11, nodeIDs: [5, 6], tags: tags),
        ]))
        let extract = try cut(builder.file)
        // This documents current behaviour (see the AreaCutter doc comment). If a per-way
        // bounding-box pass is added, this test should change to expect both ways.
        #expect(extract.ways.isEmpty)
    }

    @Test("A node ID that appears twice is rejected")
    func duplicateNodes() {
        func file(duplicatedLatitude: Double) -> Data {
            var builder = PBFFileBuilder()
            builder.appendBlob(type: "OSMHeader", payload: PBFFileBuilder.headerPayload())
            for _ in 0..<2 {
                builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(
                    strings: [""],
                    dense: PBFFileBuilder.denseNodes(
                        ids: [1, 2], latitudes: [Int64(duplicatedLatitude * 1e7), 300_000_000], longitudes: [95_000_000, 50_000_000]
                    )
                ))
            }
            builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(strings: ["", "a", "b"], ways: [
                PBFFileBuilder.way(id: 10, nodeIDs: [1, 2], tags: [(key: 1, value: 2)]),
            ]))
            return builder.file
        }
        // Node 1 is inside the box and repeated; node 2 is outside the box and repeated.
        #expect(throws: AreaCutterError.duplicateID(kind: "node", id: 1)) { try self.cut(file(duplicatedLatitude: 47.5)) }
        // Only node 2 is repeated, outside the box: found twice in the last pass.
        #expect(throws: AreaCutterError.duplicateID(kind: "node", id: 2)) {
            var builder = PBFFileBuilder()
            builder.appendBlob(type: "OSMHeader", payload: PBFFileBuilder.headerPayload())
            builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(
                strings: [""],
                dense: PBFFileBuilder.denseNodes(ids: [1], latitudes: [475_000_000], longitudes: [95_000_000])
            ))
            for _ in 0..<2 {
                builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(
                    strings: [""],
                    dense: PBFFileBuilder.denseNodes(ids: [2], latitudes: [300_000_000], longitudes: [50_000_000])
                ))
            }
            builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(strings: ["", "a", "b"], ways: [
                PBFFileBuilder.way(id: 10, nodeIDs: [1, 2], tags: [(key: 1, value: 2)]),
            ]))
            try self.cut(builder.file)
        }
    }

    @Test("A way ID that appears twice among kept ways is rejected")
    func duplicateWays() {
        var builder = PBFFileBuilder()
        builder.appendBlob(type: "OSMHeader", payload: PBFFileBuilder.headerPayload())
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(
            strings: [""],
            dense: PBFFileBuilder.denseNodes(ids: [1], latitudes: [475_000_000], longitudes: [95_000_000])
        ))
        let way = PBFFileBuilder.way(id: 10, nodeIDs: [1], tags: [(key: 1, value: 2)])
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(strings: ["", "a", "b"], ways: [way, way]))
        #expect(throws: AreaCutterError.duplicateID(kind: "way", id: 10)) { try self.cut(builder.file) }
    }

    @Test("Cutting can be cancelled")
    func cancellation() async {
        let data = World.file()
        let task = Task { () throws -> OSMExtract in
            while !Task.isCancelled { await Task.yield() }
            return try AreaCutter().cut(PBFReader(data: data), to: World.box)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("Progress reports each stage in order, skipping stages with nothing to do")
    func progressStages() throws {
        var stages: [AreaCutter.Pass] = []
        _ = try AreaCutter().cut(PBFReader(data: World.file()), to: World.box) { stages.append($0) }
        #expect(stages == [.insideNodes, .ways, .relations, .memberWays, .outsideNodes, .assembly])

        // A box with nothing in it needs neither completion nor outside nodes.
        stages = []
        _ = try AreaCutter().cut(
            PBFReader(data: World.file()), to: BoundingBox(south: 0, west: 0, north: 1, east: 1)
        ) { stages.append($0) }
        #expect(stages == [.insideNodes, .ways, .relations, .assembly])
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
        #expect(counts[.relations]! == (0, 0, 6))
        #expect(counts[.all]! == (12, 5, 6))
    }
}

@Suite("NodeTable")
struct NodeTableTests {
    private func table(_ ids: [Int64]) -> NodeTable {
        NodeTable(sorting: ids.map { NodeRecord(id: $0, latitude: 0, longitude: 0, tagStart: 0, tagCount: 0) })
    }

    @Test("An empty table contains nothing")
    func empty() {
        let empty = table([])
        #expect(!empty.contains(1))
        #expect(empty.index(of: 1) == nil)
        #expect(empty.firstDuplicateID == nil)
    }

    @Test("Finds the first, last and middle records and rejects absent IDs")
    func lookups() {
        let sorted = table([50, 10, 30, 20, 40])   // unsorted input is sorted by the table
        #expect(sorted.records.map(\.id) == [10, 20, 30, 40, 50])
        #expect(sorted.index(of: 10) == 0)
        #expect(sorted.index(of: 50) == 4)
        #expect(sorted.index(of: 30) == 2)
        #expect(!sorted.contains(5))
        #expect(!sorted.contains(25))
        #expect(!sorted.contains(60))
    }

    @Test("Handles IDs beyond 32 bits and detects duplicates")
    func largeIDsAndDuplicates() {
        let large = table([14_353_154_743, 1, 9_000_000_000_000])
        #expect(large.contains(14_353_154_743))
        #expect(large.contains(9_000_000_000_000))
        #expect(large.firstDuplicateID == nil)
        #expect(table([3, 7, 3]).firstDuplicateID == 3)
    }
}
