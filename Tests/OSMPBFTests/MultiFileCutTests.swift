import Foundation
import GeoCore
import PBFTestSupport
import Testing

@testable import OSMPBF

/// Cutting an area out of several files, as for a box over a country border.
@Suite("AreaCutter with several files")
struct MultiFileCutTests {
    private let box = BoundingBox(south: 47, west: 9, north: 48, east: 10)

    private struct Node { var id: Int64; var lat: Double; var lon: Double; var value: Int32? }
    private struct Way { var id: Int64; var nodes: [Int64]; var path = true }
    private struct Relation { var id: Int64; var members: [(id: Int64, type: UInt64)] }

    /// The string table every file uses: 1 `amenity`, 2 `cafe`, 3 `bar`, 4 `highway`, 5 `path`, 6 `type`, 7 `multipolygon`, 8 `outer`.
    private let strings = ["", "amenity", "cafe", "bar", "highway", "path", "type", "multipolygon", "outer"]

    private func file(_ nodes: [Node] = [], _ ways: [Way] = [], _ relations: [Relation] = []) -> PBFReader {
        var builder = PBFFileBuilder()
        builder.appendBlob(type: "OSMHeader", payload: PBFFileBuilder.headerPayload())
        if !nodes.isEmpty {
            builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(
                strings: strings,
                dense: PBFFileBuilder.denseNodes(
                    ids: nodes.map(\.id), latitudes: nodes.map { Int64(($0.lat * 1e7).rounded()) },
                    longitudes: nodes.map { Int64(($0.lon * 1e7).rounded()) },
                    tags: nodes.map { node in node.value.map { [(key: Int32(1), value: $0)] } ?? [] })))
        }
        if !ways.isEmpty {
            builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(
                strings: strings,
                ways: ways.map { PBFFileBuilder.way(id: $0.id, nodeIDs: $0.nodes, tags: $0.path ? [(key: 4, value: 5)] : []) }))
        }
        if !relations.isEmpty {
            builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(
                strings: strings,
                relations: relations.map {
                    PBFFileBuilder.relation(
                        id: $0.id, members: $0.members.map { (id: $0.id, role: 8, type: $0.type) }, tags: [(key: 6, value: 7)])
                }))
        }
        return try! PBFReader(data: builder.file)
    }

    @Test("A way and a relation that one file holds in part are completed from the other")
    func completedAcrossFiles() throws {
        // The way 100 and the relation 200 are in the west file; the way 101 (inside the box) and way 300, far away, in the east one.
        let west = file(
            [Node(id: 1, lat: 47.5, lon: 9.4), Node(id: 5, lat: 46.5, lon: 9.4)], [Way(id: 100, nodes: [1, 5])],
            [Relation(id: 200, members: [(100, 1), (101, 1), (300, 1)])])
        let east = file(
            [Node(id: 2, lat: 47.5, lon: 9.6), Node(id: 3, lat: 47.6, lon: 9.7), Node(id: 6, lat: 46.5, lon: 9.6),
             Node(id: 7, lat: 40, lon: 5), Node(id: 8, lat: 40.1, lon: 5.1)],
            [Way(id: 101, nodes: [2, 3, 6]), Way(id: 300, nodes: [7, 8])])
        let extract = try AreaCutter().cut([west, east], to: box)
        #expect(extract.ways.map(\.id) == [100, 101, 300])
        #expect(extract.nodes.map(\.id) == [1, 2, 3, 5, 6, 7, 8])
        #expect(extract.missingNodeCount == 0)
        let relation = try #require(extract.relations.first { $0.relation.id == 200 })
        #expect(relation.isComplete, "the way 300 only the other file has is found")
        // One file alone gives half a map.
        let alone = try AreaCutter().cut(west, to: box)
        #expect(alone.ways.map(\.id) == [100] && alone.relations.first?.isComplete == false)
    }

    @Test("An object in both files is taken from the first, so the order of the files decides")
    func firstFileWins() throws {
        let a = file([Node(id: 1, lat: 47.5, lon: 9.5, value: 2)], [Way(id: 100, nodes: [1, 1])])
        let b = file([Node(id: 1, lat: 47.5, lon: 9.5, value: 3)], [Way(id: 100, nodes: [1, 1], path: false)])
        let ab = try AreaCutter().cut([a, b], to: box)
        #expect(ab.node(withID: 1)?.tags == ["amenity": "cafe"])
        #expect(ab.ways.first?.tags == ["highway": "path"])
        let ba = try AreaCutter().cut([b, a], to: box)
        #expect(ba.node(withID: 1)?.tags == ["amenity": "bar"])
        #expect(ba.ways.first?.tags.isEmpty == true)
        #expect(ab.nodes.count == 1 && ab.ways.count == 1)
    }

    @Test("The same ID twice inside one file is still an error")
    func duplicateInOneFile() throws {
        let a = file([Node(id: 1, lat: 47.5, lon: 9.5), Node(id: 1, lat: 47.6, lon: 9.5)], [Way(id: 100, nodes: [1, 1])])
        #expect(throws: AreaCutterError.self) { try AreaCutter().cut([a, a], to: box) }
    }

    @Test("No file is an error, and one file gives the same as the single-file cut")
    func oneAndNone() throws {
        #expect(throws: AreaCutterError.noInput) { try AreaCutter().cut([], to: box) }
        let a = file([Node(id: 1, lat: 47.5, lon: 9.5, value: 2)], [Way(id: 100, nodes: [1, 1])])
        let one = try AreaCutter().cut([a], to: box), single = try AreaCutter().cut(a, to: box)
        #expect(one.nodes.map(\.id) == single.nodes.map(\.id) && one.ways.map(\.id) == single.ways.map(\.id))
    }

    @Test("A copy of a relation that touches the area is not replaced by another file's copy that is only a parent")
    func touchingCopyIsKept() throws {
        // File A has 200 as a parent of relation 1; file B has it listing the way 100, which is in the area.
        let nodes = [Node(id: 1, lat: 47.5, lon: 9.5), Node(id: 5, lat: 46.5, lon: 9.5)]
        let a = file(nodes, [Way(id: 100, nodes: [1, 5])],
            [Relation(id: 1, members: [(100, 1)]), Relation(id: 200, members: [(1, 2)])])
        let b = file([], [], [Relation(id: 200, members: [(100, 1)])])
        for order in [[a, b], [b, a]] {
            let extract = try AreaCutter().cut(order, to: box)
            let relation = try #require(extract.relations.first { $0.relation.id == 200 })
            #expect(extract.relations.map(\.relation.id) == [1, 200])
            // Whichever copy is taken, it is taken once and not replaced by the other.
            #expect(relation.relation.members.count == 1)
        }
        let touchingFirst = try AreaCutter().cut([b, a], to: box)
        #expect(touchingFirst.relations.first { $0.relation.id == 200 }?.relation.members.first?.type == .way)
        let touchingLast = try AreaCutter().cut([a, b], to: box)
        #expect(touchingLast.relations.first { $0.relation.id == 200 }?.relation.members.first?.type == .way,
            "the copy that touches the area wins over a parent copy that came first")
    }

    /// Objects spread over two files, some in both, give the cut of the single file that holds them all.
    @Test("Spreading a world over two or three files at random gives the same cut as one file", arguments: 0..<40)
    func randomSplit(seed: Int) throws {
        let fileCount = seed < 20 ? 2 : 3
        var generator = SplitMix(seed: UInt64(seed) &+ 1)
        let nodes = [
            Node(id: 1, lat: 47.5, lon: 9.5), Node(id: 2, lat: 47.6, lon: 9.6, value: 2), Node(id: 4, lat: 46.5, lon: 9.5),
            Node(id: 5, lat: 40.0, lon: 5.0), Node(id: 6, lat: 40.1, lon: 5.1), Node(id: 7, lat: 39.0, lon: 4.0),
            Node(id: 8, lat: 39.1, lon: 4.1), Node(id: 9, lat: 47.2, lon: 9.2), Node(id: 10, lat: 41.0, lon: 6.0, value: 3),
        ]
        let ways = [
            Way(id: 100, nodes: [1, 4]), Way(id: 101, nodes: [5, 6]), Way(id: 102, nodes: [7, 8]), Way(id: 103, nodes: [9, 4]),
        ]
        let relations = [
            Relation(id: 200, members: [(100, 1), (102, 1), (10, 0)]),
            Relation(id: 202, members: [(200, 2)]),
            Relation(id: 205, members: [(202, 2)]),
            Relation(id: 204, members: [(2, 0)]),
            Relation(id: 201, members: [(101, 1)]),
        ]
        // Each item goes to a random non-empty set of the files: in one, in several or in all.
        func share<T>(_ items: [T]) -> [[T]] {
            var files = [[T]](repeating: [], count: fileCount)
            for item in items {
                let mask = Int(generator.next() % UInt64((1 << fileCount) - 1)) + 1
                for index in 0..<fileCount where mask & (1 << index) != 0 { files[index].append(item) }
            }
            return files
        }
        let n = share(nodes), w = share(ways), r = share(relations)
        let whole = try AreaCutter().cut(file(nodes, ways, relations), to: box)
        let split = try AreaCutter().cut((0..<fileCount).map { file(n[$0], w[$0], r[$0]) }, to: box)
        #expect(split.nodes.map(\.id) == whole.nodes.map(\.id))
        #expect(split.ways.map(\.id) == whole.ways.map(\.id))
        #expect(split.relations.map(\.relation.id) == whole.relations.map(\.relation.id))
        #expect(split.relations.map(\.isComplete) == whole.relations.map(\.isComplete))
        #expect(split.missingNodeCount == whole.missingNodeCount)
    }
}

/// A small deterministic random number generator for the split test.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
