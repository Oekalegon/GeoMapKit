import Foundation
import Testing
import GeoCore
@testable import OSMPBF

@Suite("Extract accessors")
struct ExtractAccessorTests {
    private func raw(_ degrees: Double) -> Int64 { Int64((degrees * 1e7).rounded()) }

    /// Nodes 1 (inside) and 2 (outside); way 10 over both; relation 20 with a way, a node, a missing way and a role.
    private func file() -> Data {
        var builder = PBFFileBuilder()
        builder.appendBlob(type: "OSMHeader", payload: PBFFileBuilder.headerPayload())
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(
            strings: [""],
            dense: PBFFileBuilder.denseNodes(ids: [1, 2], latitudes: [raw(47.5), raw(30)], longitudes: [raw(9.5), raw(5)])
        ))
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(
            strings: ["", "highway", "path"], ways: [PBFFileBuilder.way(id: 10, nodeIDs: [1, 2], tags: [(key: 1, value: 2)])]
        ))
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(
            strings: ["", "type", "route", "forward", "stop", "name", "Test route"],
            relations: [PBFFileBuilder.relation(
                id: 20,
                // Way 10 is kept; way 11 does not exist in the file, so the relation is incomplete.
                members: [(id: 10, role: 3, type: 1), (id: 1, role: 4, type: 0), (id: 11, role: 0, type: 1)],
                tags: [(key: 1, value: 2), (key: 5, value: 6)]
            )]
        ))
        return builder.file
    }

    private func cut(_ data: Data, box: BoundingBox = BoundingBox(south: 47, west: 9, north: 48, east: 10)) throws -> OSMExtract {
        try AreaCutter().cut(PBFReader(data: data), to: box)
    }

    @Test("Relation accessors: members with roles, tags, completeness and counts")
    func relations() throws {
        let extract = try cut(file())
        let relations = extract.relations
        #expect(relations.ids == [20])
        #expect(relations.count == 1)
        #expect(relations.memberCount == 3)
        #expect(!relations.isComplete(at: 0))                      // way 11 is not in the file
        #expect(relations.tags(at: 0).dictionary == ["type": "route", "name": "Test route"])
        let relation = relations[0]
        #expect(relation.isComplete == false)
        #expect(relation.relation.members == [
            OSMMember(type: .way, id: 10, role: "forward"),
            OSMMember(type: .node, id: 1, role: "stop"),
            OSMMember(type: .way, id: 11, role: ""),
        ])
    }

    @Test("Way accessors: lookup by ID, node IDs and tags")
    func ways() throws {
        let extract = try cut(file())
        #expect(extract.ways.index(ofID: 10) == 0)
        #expect(extract.ways.index(ofID: 99) == nil)
        #expect(Array(extract.ways.nodeIDs(at: 0)) == [1, 2])
        #expect(extract.ways.tags(at: 0)["highway"] == "path")
        #expect(extract.ways.vertexCount == 2)
    }

    @Test("An empty extract has empty collections and only the empty string")
    func emptyExtract() throws {
        let extract = try cut(file(), box: BoundingBox(south: 0, west: 0, north: 1, east: 1))
        #expect(extract.nodes.isEmpty)
        #expect(extract.ways.isEmpty)
        #expect(extract.relations.isEmpty)
        #expect(extract.nodes.ids.isEmpty)
        #expect(extract.node(withID: 1) == nil)
        #expect(extract.strings.count == 1)                        // just ""
        #expect(extract.strings.string(at: 0) == "")
        #expect(extract.memoryBytes > 0)
    }

    @Test("Two tag keys that differ only in Unicode normalization both survive the reader and the extract")
    func equivalentKeysSurvive() throws {
        var builder = PBFFileBuilder()
        builder.appendBlob(type: "OSMHeader", payload: PBFFileBuilder.headerPayload())
        let precomposed = "caf\u{00E9}", decomposed = "cafe\u{0301}"
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(
            strings: ["", precomposed, decomposed, "v1", "v2"],
            dense: PBFFileBuilder.denseNodes(
                ids: [1], latitudes: [raw(47.5)], longitudes: [raw(9.5)],
                tags: [[(key: 1, value: 3), (key: 2, value: 4)]]
            ),
            ways: [PBFFileBuilder.way(id: 10, nodeIDs: [1, 1], tags: [(key: 1, value: 3), (key: 2, value: 4)])]
        ))
        var nodeTags: [[OSMTag]] = [], wayTags: [[OSMTag]] = []
        try PBFReader(data: builder.file).forEachBlock {
            nodeTags += $0.nodes.map(\.orderedTags)
            wayTags += $0.ways.map(\.orderedTags)
        }
        #expect(nodeTags.count == 1 && nodeTags[0].count == 2)
        #expect(wayTags.count == 1 && wayTags[0].count == 2)
        // They are separate keys with their own values, and the order is by key bytes: "caf\u{00E9}" (c3 a9) before "cafe\u{0301}" (65).
        let byBytes = nodeTags[0].map { Array($0.key.utf8) }
        #expect(byBytes == [Array("cafe\u{0301}".utf8), Array("caf\u{00E9}".utf8)].sorted { $0.lexicographicallyPrecedes($1) })
        #expect(Set(nodeTags[0].map { Array($0.key.utf8) }).count == 2)
        #expect(nodeTags[0].first { $0.key.utf8.elementsEqual(precomposed.utf8) }?.value == "v1")
        #expect(nodeTags[0].first { $0.key.utf8.elementsEqual(decomposed.utf8) }?.value == "v2")
    }

    @Test("Both keys reach the compact extract and are found by their own bytes")
    func equivalentKeysInExtract() throws {
        var builder = PBFFileBuilder()
        builder.appendBlob(type: "OSMHeader", payload: PBFFileBuilder.headerPayload())
        let precomposed = "caf\u{00E9}", decomposed = "cafe\u{0301}"
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(
            strings: ["", precomposed, decomposed, "v1", "v2"],
            dense: PBFFileBuilder.denseNodes(
                ids: [1], latitudes: [raw(47.5)], longitudes: [raw(9.5)],
                tags: [[(key: 1, value: 3), (key: 2, value: 4)]]
            )
        ))
        let extract = try cut(builder.file)
        let tags = extract.nodes.tags(at: 0)
        #expect(tags.count == 2)
        #expect(tags[precomposed] == "v1")
        #expect(tags[decomposed] == "v2")
        #expect(Array(tags).count == 2)
    }

    @Test("Identical keys are all kept, in file order")
    func duplicateKeys() throws {
        var builder = PBFFileBuilder()
        builder.appendBlob(type: "OSMHeader", payload: PBFFileBuilder.headerPayload())
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(
            strings: ["", "name", "first", "second"],
            dense: PBFFileBuilder.denseNodes(
                ids: [1], latitudes: [raw(47.5)], longitudes: [raw(9.5)],
                tags: [[(key: 1, value: 2), (key: 1, value: 3)]]
            )
        ))
        var tags: [OSMTag] = []
        try PBFReader(data: builder.file).forEachBlock { tags += $0.nodes.flatMap(\.orderedTags) }
        #expect(tags.map(\.value) == ["first", "second"])
        // The dictionary convenience is lossy: the last value wins.
        var dictionary: [String: String] = [:]
        try PBFReader(data: builder.file).forEachBlock { dictionary = $0.nodes[0].tags }
        #expect(dictionary == ["name": "second"])
    }

    @Test("Elements built from a dictionary and from an ordered list agree, and order is by key bytes")
    func initialisersAgree() {
        let fromDictionary = OSMNode(id: 1, coordinate: Coordinate(latitude: 1, longitude: 2), tags: ["b": "2", "a": "1"])
        let fromList = OSMNode(id: 1, coordinate: Coordinate(latitude: 1, longitude: 2), orderedTags: [OSMTag(key: "b", value: "2"), OSMTag(key: "a", value: "1")])
        #expect(fromDictionary == fromList)
        #expect(fromList.orderedTags.map(\.key) == ["a", "b"])
        #expect(fromList.tags == ["a": "1", "b": "2"])
    }

    @Test("Looking up a tag key compares bytes, not Swift string equality")
    func byteExactLookup() throws {
        var builder = PBFFileBuilder()
        builder.appendBlob(type: "OSMHeader", payload: PBFFileBuilder.headerPayload())
        let precomposed = "caf\u{00E9}", decomposed = "cafe\u{0301}"
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(
            strings: ["", precomposed, "value"],
            dense: PBFFileBuilder.denseNodes(ids: [1], latitudes: [raw(47.5)], longitudes: [raw(9.5)], tags: [[(key: 1, value: 2)]])
        ))
        let extract = try cut(builder.file)
        let tags = extract.nodes.tags(at: 0)
        #expect(tags[precomposed] == "value")
        #expect(tags[decomposed] == nil)          // equal as Swift strings, different bytes
    }
}
