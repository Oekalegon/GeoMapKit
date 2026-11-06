import Foundation
import Testing
import GeoCore
@testable import OSMPBF

/// The expected content of the test file, in OSM's 1e-7 degree units.
private enum Fixture {
    static let strings = [
        "", "highway", "path", "name", "Test Path", "natural", "water",
        "type", "multipolygon", "outer", "inner", "surface", "gravel", "peak",
    ]

    static var file: Data {
        var builder = PBFFileBuilder()
        builder.appendBlob(
            type: "OSMHeader",
            payload: PBFFileBuilder.headerPayload(
                optional: ["Sort.Type_then_ID"],
                bbox: (left: 10_000_000_000, right: 11_000_000_000, top: 60_000_000_000, bottom: 59_000_000_000)
            )
        )
        let dense = PBFFileBuilder.denseNodes(
            ids: [1000, 1001, 1002, 1003],
            latitudes: [599_139_000, 599_140_000, 600_000_000, 601_000_000],
            longitudes: [107_522_000, 107_530_000, 108_000_000, 109_000_000],
            tags: [[], [], [], [(key: 5, value: 13)]]   // node 1003: natural=peak
        )
        let pathWay = PBFFileBuilder.way(
            id: 2000, nodeIDs: [1000, 1001, 1002],
            tags: [(1, 2), (11, 12), (3, 4)]            // highway=path, surface=gravel, name=Test Path
        )
        let lakeWay = PBFFileBuilder.way(
            id: 2001, nodeIDs: [1000, 1001, 1002, 1000],
            tags: [(5, 6)]                               // natural=water
        )
        let relation = PBFFileBuilder.relation(
            id: 3000,
            members: [(id: 2001, role: 9, type: 1), (id: 2000, role: 10, type: 1), (id: 1003, role: 0, type: 0)],
            tags: [(7, 8)]                               // type=multipolygon
        )
        builder.appendBlob(
            type: "OSMData",
            payload: PBFFileBuilder.primitiveBlock(strings: strings, dense: dense, ways: [pathWay, lakeWay], relations: [relation])
        )
        return builder.file
    }
}

@Suite("PBFReader")
struct PBFReaderTests {
    @Test("Reads the header")
    func header() throws {
        let header = try PBFReader(data: Fixture.file).header()
        #expect(header.requiredFeatures == ["OsmSchema-V0.6", "DenseNodes"])
        #expect(header.optionalFeatures == ["Sort.Type_then_ID"])
        #expect(header.writingProgram == "GeoMapKitTests")
        #expect(header.boundingBox == BoundingBox(south: 59, west: 10, north: 60, east: 11))
    }

    @Test("Reads dense nodes with exact coordinates and tags")
    func nodes() throws {
        var blocks: [OSMBlock] = []
        try PBFReader(data: Fixture.file).forEachBlock { blocks.append($0) }
        let nodes = try #require(blocks.first).nodes
        #expect(nodes.map(\.id) == [1000, 1001, 1002, 1003])
        // 1e-7 degree units must come out exactly as the decimal literals.
        #expect(nodes[0].coordinate == Coordinate(latitude: 59.9139, longitude: 10.7522))
        #expect(nodes[1].coordinate == Coordinate(latitude: 59.914, longitude: 10.753))
        #expect(nodes[3].coordinate == Coordinate(latitude: 60.1, longitude: 10.9))
        #expect(nodes[0].tags.isEmpty)
        #expect(nodes[3].tags == ["natural": "peak"])
    }

    @Test("Reads ways with delta-coded node references and every tag")
    func ways() throws {
        var blocks: [OSMBlock] = []
        try PBFReader(data: Fixture.file).forEachBlock { blocks.append($0) }
        let ways = try #require(blocks.first).ways
        #expect(ways.count == 2)
        #expect(ways[0].id == 2000)
        #expect(ways[0].nodeIDs == [1000, 1001, 1002])
        #expect(ways[0].tags == ["highway": "path", "surface": "gravel", "name": "Test Path"])
        #expect(!ways[0].isClosed)
        #expect(ways[1].nodeIDs == [1000, 1001, 1002, 1000])
        #expect(ways[1].isClosed)
    }

    @Test("Reads relations with member types and roles")
    func relations() throws {
        var blocks: [OSMBlock] = []
        try PBFReader(data: Fixture.file).forEachBlock { blocks.append($0) }
        let relation = try #require(blocks.first?.relations.first)
        #expect(relation.id == 3000)
        #expect(relation.tags == ["type": "multipolygon"])
        #expect(relation.members == [
            OSMMember(type: .way, id: 2001, role: "outer"),
            OSMMember(type: .way, id: 2000, role: "inner"),
            OSMMember(type: .node, id: 1003, role: ""),
        ])
    }

    @Test("Uncompressed blobs read the same as compressed ones")
    func rawBlobs() throws {
        var builder = PBFFileBuilder()
        builder.appendBlob(type: "OSMHeader", payload: PBFFileBuilder.headerPayload(), compression: .raw)
        let dense = PBFFileBuilder.denseNodes(ids: [1], latitudes: [599_139_000], longitudes: [107_522_000])
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(strings: [""], dense: dense), compression: .raw)
        var count = 0
        try PBFReader(data: builder.file).forEachBlock { count += $0.nodes.count }
        #expect(count == 1)
    }

    @Test("Granularity and offsets are applied: degrees = (offset + granularity × value) / 1e9")
    func granularityAndOffsets() throws {
        var builder = PBFFileBuilder()
        builder.appendBlob(type: "OSMHeader", payload: PBFFileBuilder.headerPayload())
        // granularity 1000 (1e-6 degrees), offsets of 1 degree.
        let dense = PBFFileBuilder.denseNodes(ids: [1], latitudes: [58_913_900], longitudes: [9_752_200])
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(
            strings: [""], dense: dense, granularity: 1000,
            latitudeOffset: 1_000_000_000, longitudeOffset: 1_000_000_000
        ))
        var nodes: [OSMNode] = []
        try PBFReader(data: builder.file).forEachBlock { nodes += $0.nodes }
        #expect(nodes[0].coordinate == Coordinate(latitude: 59.9139, longitude: 10.7522))
    }

    @Test("Reads a file from disk through a memory map")
    func readsFromURL() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-\(UUID().uuidString).osm.pbf")
        try Fixture.file.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var wayCount = 0
        try PBFReader(url: url).forEachBlock { wayCount += $0.ways.count }
        #expect(wayCount == 2)
    }

    @Test("Several data blocks are delivered in order and unknown blob types are skipped")
    func multipleBlocks() throws {
        var builder = PBFFileBuilder()
        builder.appendBlob(type: "OSMHeader", payload: PBFFileBuilder.headerPayload())
        builder.appendBlob(type: "SomethingElse", payload: Data([1, 2, 3]), compression: .raw)
        for first in [1, 11] as [Int64] {
            let dense = PBFFileBuilder.denseNodes(ids: [first, first + 1], latitudes: [1, 2], longitudes: [1, 2])
            builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(strings: [""], dense: dense))
        }
        var ids: [Int64] = []
        try PBFReader(data: builder.file).forEachBlock { ids += $0.nodes.map(\.id) }
        #expect(ids == [1, 2, 11, 12])
    }
}
