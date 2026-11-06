import Foundation
import Testing
import GeoCore
@testable import OSMPBF

@Suite("StringInterner")
struct StringInternerTests {
    @Test("The empty string is ID 0 and equal strings get the same ID")
    func basics() throws {
        var interner = StringInterner()
        #expect(try interner.intern("") == 0)
        let a = try interner.intern("highway")
        let b = try interner.intern("path")
        #expect(a != b)
        #expect(try interner.intern("highway") == a)
        let table = interner.frozen()
        #expect(table.string(at: a) == "highway")
        #expect(table.string(at: b) == "path")
        #expect(table.string(at: 0) == "")
        #expect(table.string(at: 99) == nil)
        #expect(table.count == 3)
    }

    @Test("Strings that Swift considers equal but whose bytes differ are kept apart")
    func canonicallyEquivalentStringsStayDistinct() throws {
        // "é" as one scalar and as "e" plus a combining accent compare equal in Swift but are different data.
        let precomposed = "caf\u{00E9}"
        let decomposed = "cafe\u{0301}"
        #expect(precomposed == decomposed)
        #expect(Array(precomposed.utf8) != Array(decomposed.utf8))
        var interner = StringInterner()
        let first = try interner.intern(precomposed)
        let second = try interner.intern(decomposed)
        #expect(first != second)
        let table = interner.frozen()
        #expect(Array(table.string(at: first)!.utf8) == Array(precomposed.utf8))
        #expect(Array(table.string(at: second)!.utf8) == Array(decomposed.utf8))
    }

    @Test("Many strings, beyond several table growths, all come back exactly")
    func growth() throws {
        var interner = StringInterner()
        let strings = (0..<20_000).map { "string-\($0)-\(String(repeating: "x", count: $0 % 17))" }
        let ids = try strings.map { try interner.intern($0) }
        #expect(Set(ids).count == strings.count)
        // Interning again returns the same IDs.
        #expect(try strings.map { try interner.intern($0) } == ids)
        let table = interner.frozen()
        for (string, id) in zip(strings, ids) { #expect(table.string(at: id) == string) }
    }

    @Test("Unicode, emoji and long strings round trip")
    func unicode() throws {
        var interner = StringInterner()
        let samples = ["Färchaneggweg", "日本語", "🏔️ peak", String(repeating: "å", count: 5_000)]
        let ids = try samples.map { try interner.intern($0) }
        let table = interner.frozen()
        #expect(ids.map { table.string(at: $0) } == samples.map { Optional($0) })
    }
}

@Suite("SortedIDs")
struct SortedIDsTests {
    @Test("Sorts, removes duplicates and searches")
    func basics() {
        let set = SortedIDs(unsorted: [30, 10, 20, 10, 30, 14_353_154_743])
        #expect(set.ids == [10, 20, 30, 14_353_154_743])
        #expect(set.contains(20))
        #expect(set.contains(14_353_154_743))
        #expect(!set.contains(25))
        #expect(!SortedIDs(unsorted: []).contains(1))
    }
}

/// A small world, cut with the cutter, to check the compact representation end to end.
@Suite("Compact extract")
struct CompactExtractTests {
    private func extract() throws -> OSMExtract {
        func raw(_ degrees: Double) -> Int64 { Int64((degrees * 1e7).rounded()) }
        var builder = PBFFileBuilder()
        builder.appendBlob(type: "OSMHeader", payload: PBFFileBuilder.headerPayload())
        let strings = ["", "name", "Test Path", "highway", "path", "surface", "gravel", "amenity", "cafe"]
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(
            strings: strings,
            dense: PBFFileBuilder.denseNodes(
                ids: [1, 2, 3], latitudes: [raw(47.5), raw(47.6), raw(40)], longitudes: [raw(9.5), raw(9.6), raw(5)],
                // Node 2 has two tags, listed in an order that is not sorted by key.
                tags: [[], [(key: 7, value: 8), (key: 1, value: 2)], []]
            )
        ))
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(strings: strings, ways: [
            PBFFileBuilder.way(id: 10, nodeIDs: [1, 2, 3], tags: [(key: 5, value: 6), (key: 3, value: 4), (key: 1, value: 2)]),
        ]))
        return try AreaCutter().cut(PBFReader(data: builder.file), to: BoundingBox(south: 47, west: 9, north: 48, east: 10))
    }

    @Test("Tags come back in key order, whatever order the file lists them in")
    func tagOrder() throws {
        let extract = try extract()
        let way = try #require(extract.ways.index(ofID: 10))
        #expect(extract.ways.tags(at: way).map(\.key) == ["highway", "name", "surface"])
        let node = try #require(extract.nodes.index(ofID: 2))
        #expect(extract.nodes.tags(at: node).map(\.key) == ["amenity", "name"])
    }

    @Test("A tag list gives values by key, as a dictionary and without building one")
    func tagList() throws {
        let extract = try extract()
        let way = try #require(extract.ways.index(ofID: 10))
        let tags = extract.ways.tags(at: way)
        #expect(tags.count == 3)
        #expect(!tags.isEmpty)
        #expect(tags["highway"] == "path")
        #expect(tags["surface"] == "gravel")
        #expect(tags["name"] == "Test Path")
        #expect(tags["missing"] == nil)
        #expect(tags.dictionary == ["highway": "path", "surface": "gravel", "name": "Test Path"])
        let untagged = try #require(extract.nodes.index(ofID: 1))
        #expect(extract.nodes.tags(at: untagged).isEmpty)
        #expect(!extract.nodes.hasTags(at: untagged))
        #expect(extract.nodes.hasTags(at: try #require(extract.nodes.index(ofID: 2))))
    }

    @Test("Columns agree with the values built on demand")
    func columnsAgreeWithElements() throws {
        let extract = try extract()
        #expect(extract.nodes.ids == [1, 2, 3])
        for position in extract.nodes.indices {
            let node = extract.nodes[position]
            #expect(node.id == extract.nodes.ids[position])
            #expect(node.coordinate == extract.nodes.coordinate(at: position))
            #expect(node.tags == extract.nodes.tags(at: position).dictionary)
        }
        let way = extract.ways[0]
        #expect(way.nodeIDs == Array(extract.ways.nodeIDs(at: 0)))
        #expect(extract.ways.vertexCount == 3)
        #expect(extract.node(withID: 2)?.tags == ["amenity": "cafe", "name": "Test Path"])
        #expect(extract.node(withID: 99) == nil)
    }

    @Test("Coordinates come out as the exact decimal values")
    func coordinates() throws {
        let extract = try extract()
        #expect(extract.node(withID: 1)?.coordinate == Coordinate(latitude: 47.5, longitude: 9.5))
        #expect(extract.node(withID: 3)?.coordinate == Coordinate(latitude: 40, longitude: 5))
    }

    @Test("The shared string table holds each string once and the extract reports its memory")
    func stringsAndMemory() throws {
        let extract = try extract()
        // "", name, Test Path, highway, path, surface, gravel, amenity, cafe
        #expect(extract.strings.count == 9)
        #expect(extract.memoryBytes > 0)
        #expect(extract.memoryBytes == extract.nodes.memoryBytes + extract.ways.memoryBytes
            + extract.relations.memoryBytes + extract.strings.memoryBytes)
    }

    @Test("A node outside the box with a coordinate beyond the globe is rejected")
    func invalidOutsideCoordinate() throws {
        var builder = PBFFileBuilder()
        builder.appendBlob(type: "OSMHeader", payload: PBFFileBuilder.headerPayload())
        // Node 2 has latitude 95 degrees: not a position on Earth.
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(
            strings: [""],
            dense: PBFFileBuilder.denseNodes(ids: [1, 2], latitudes: [475_000_000, 950_000_000], longitudes: [95_000_000, 50_000_000])
        ))
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(strings: ["", "a", "b"], ways: [
            PBFFileBuilder.way(id: 10, nodeIDs: [1, 2], tags: [(key: 1, value: 2)]),
        ]))
        #expect(throws: PBFError.self) {
            try AreaCutter().cut(PBFReader(data: builder.file), to: BoundingBox(south: 47, west: 9, north: 48, east: 10))
        }
    }

    @Test("Canonically equivalent tag values in different objects are both kept exactly")
    func equivalentValuesKeptExactly() throws {
        func raw(_ degrees: Double) -> Int64 { Int64((degrees * 1e7).rounded()) }
        var builder = PBFFileBuilder()
        builder.appendBlob(type: "OSMHeader", payload: PBFFileBuilder.headerPayload())
        let precomposed = "caf\u{00E9}", decomposed = "cafe\u{0301}"
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(
            strings: ["", "name", precomposed, decomposed],
            dense: PBFFileBuilder.denseNodes(
                ids: [1, 2], latitudes: [raw(47.5), raw(47.6)], longitudes: [raw(9.5), raw(9.6)],
                tags: [[(key: 1, value: 2)], [(key: 1, value: 3)]]
            )
        ))
        let extract = try AreaCutter().cut(
            PBFReader(data: builder.file), to: BoundingBox(south: 47, west: 9, north: 48, east: 10)
        )
        let first = try #require(extract.node(withID: 1)?.tags["name"])
        let second = try #require(extract.node(withID: 2)?.tags["name"])
        #expect(Array(first.utf8) == Array(precomposed.utf8))
        #expect(Array(second.utf8) == Array(decomposed.utf8))
    }
}
