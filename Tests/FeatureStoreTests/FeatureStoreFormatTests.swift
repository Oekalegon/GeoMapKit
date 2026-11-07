import Foundation
import GeoCore
import Testing

@testable import FeatureStore

/// Builds a small store with two cells, all three bands, tags and a relation.
private struct Sample {
    var writer = FeatureStoreWriter(
        boundingBox: BoundingBox(south: 47.0, west: 9.4, north: 47.3, east: 9.7),
        attribution: "© OpenStreetMap contributors, ODbL", sourceDate: Date(timeIntervalSince1970: 1_762_000_000),
        classifierVersion: 7)
    let cellA = TileID(zoom: 13, x: 4_285, y: 2_850)!
    let cellB = TileID(zoom: 13, x: 4_286, y: 2_850)!
    var highway: UInt32 = 0
    var name: UInt32 = 0

    init(reversed: Bool = false) throws {
        highway = writer.intern("highway")
        let path = writer.intern("path")
        let nameKey = writer.intern("name")
        name = writer.intern("Rheinweg")
        let tags = [StoredTag(key: highway, value: path), StoredTag(key: nameKey, value: name)]
        let line = GeometryPart(points: [
            PackedPoint(longitude: 95_000_000, latitude: 470_900_000 / 10 * 10),
            PackedPoint(longitude: 95_000_100, latitude: 470_900_050),
            PackedPoint(longitude: 94_999_900, latitude: 470_900_200),
        ])
        let ring = GeometryPart(
            points: [
                PackedPoint(longitude: 95_000_000, latitude: 470_000_000),
                PackedPoint(longitude: 95_000_500, latitude: 470_000_000),
                PackedPoint(longitude: 95_000_500, latitude: 470_000_500),
                PackedPoint(longitude: 95_000_000, latitude: 470_000_000),
            ], artificialEdges: [1..<2])
        let features: [(StoredFeature, ZoomBand, TileID)] = [
            (StoredFeature(classID: 1, subclass: 3, kind: .line, objectType: .way, objectID: 4_000_000_001,
                flags: [.continuesAfter], offsetAlongLine: 0, nameID: name, tags: tags, parts: [line]), .detail, cellA),
            (StoredFeature(classID: 1, subclass: 3, kind: .line, objectType: .way, objectID: 4_000_000_001,
                flags: [.continuesAfter], nameID: name, parts: [line]), .mid, cellA),
            (StoredFeature(classID: 9, kind: .area, objectType: .relation, objectID: -5, flags: [.incomplete],
                tags: [StoredTag(key: highway, value: highway)], parts: [ring]), .detail, cellA),
            (StoredFeature(classID: 1, kind: .line, objectType: .way, objectID: 4_000_000_001,
                flags: [.continuesBefore], offsetAlongLine: 123_456, nameID: name, tags: tags, parts: [line]), .detail, cellB),
            (StoredFeature(classID: 12, kind: .point, objectType: .node, objectID: 77, tags: tags,
                parts: [GeometryPart(points: [PackedPoint(longitude: 95_000_001, latitude: 470_000_001)])]), .detail, cellB),
        ]
        for (feature, band, cell) in reversed ? features.reversed() : features { try writer.add(feature, band: band, cell: cell) }
        let role = writer.intern("outer")
        try writer.add(StoredRelation(id: 99, isIncomplete: true, tags: tags,
            members: [StoredRelationMember(type: .way, id: 4_000_000_001, role: role)]))
        try writer.add(StoredRelation(id: 5, tags: [], members: []))
    }
}

@Suite("Feature store format")
struct FeatureStoreFormatTests {
    @Test("Round trip keeps features, strings, relations and header values")
    func roundTrip() throws {
        let sample = try Sample()
        let file = try FeatureStoreFile(data: try sample.writer.data())
        try file.verify()
        #expect(file.formatVersion == 1)
        #expect(file.classifierVersion == 7)
        #expect(file.storageZoom == 13)
        #expect(file.cellCount == 2)
        #expect(file.attribution == "© OpenStreetMap contributors, ODbL")
        #expect(file.sourceDate == Date(timeIntervalSince1970: 1_762_000_000))
        #expect(file.bands == [.mid, .detail])
        #expect(try file.cells() == [sample.cellA, sample.cellB])

        let detail = try file.features(in: sample.cellA, band: .detail)
        #expect(detail.map(\.classID) == [1, 9])
        let way = try #require(detail.first)
        #expect(way.objectID == 4_000_000_001 && way.subclass == 3 && way.flags == [.continuesAfter])
        #expect(way.parts[0].points.count == 3 && way.parts[0].points[2] == PackedPoint(longitude: 94_999_900, latitude: 470_900_200))
        #expect(way.tags.count == 2)
        #expect(file.string(at: way.tags[0].key) == "highway" && file.string(at: way.tags[0].value) == "path")
        #expect(file.string(at: try #require(way.nameID)) == "Rheinweg")
        let area = detail[1]
        #expect(area.objectType == .relation && area.objectID == -5 && area.flags == [.incomplete])
        #expect(area.parts[0].artificialEdges == [1..<2])

        let piece = try #require(try file.features(in: sample.cellB, band: .detail).first { $0.classID == 1 })
        #expect(piece.flags == [.continuesBefore] && piece.offsetAlongLine == 123_456)

        let relation = try #require(try file.relation(withID: 99))
        #expect(relation.isIncomplete && relation.members.count == 1 && relation.tags.count == 2)
        #expect(file.string(at: relation.members[0].role) == "outer")
        #expect(try file.relation(withID: 5)?.members.isEmpty == true)
        #expect(try file.relation(withID: 6) == nil)
    }

    @Test("Lower bands carry the name but no tags")
    func lowerBandsHaveNoTags() throws {
        let sample = try Sample()
        let file = try FeatureStoreFile(data: try sample.writer.data())
        let mid = try file.features(in: sample.cellA, band: .mid)
        #expect(mid.count == 1 && mid[0].tags.isEmpty && mid[0].nameID != nil)
        #expect(try file.features(in: sample.cellA, band: .overview).isEmpty)
    }

    @Test("A class filter returns only those classes")
    func classFilter() throws {
        let sample = try Sample()
        let file = try FeatureStoreFile(data: try sample.writer.data())
        #expect(try file.features(in: sample.cellA, band: .detail, classes: [9]).map(\.classID) == [9])
        #expect(try file.features(in: sample.cellA, band: .detail, classes: [200]).isEmpty)
    }

    @Test("An unknown cell is empty, and a wrong zoom is not found")
    func missingCell() throws {
        let sample = try Sample()
        let file = try FeatureStoreFile(data: try sample.writer.data())
        #expect(try file.features(in: TileID(zoom: 13, x: 1, y: 1)!, band: .detail).isEmpty)
        #expect(try file.containsCell(TileID(zoom: 12, x: 2_142, y: 1_425)!) == false)
    }

    @Test("Output does not depend on the order features were added")
    func deterministic() throws {
        let forward = try Sample().writer.data()
        let backward = try Sample(reversed: true).writer.data()
        #expect(forward == backward)
        let a = try FeatureStoreFile(data: forward), b = try FeatureStoreFile(data: backward)
        let cell = TileID(zoom: 13, x: 4_285, y: 2_850)!
        let fa = try a.features(in: cell, band: .detail).map { $0.objectID }
        let fb = try b.features(in: cell, band: .detail).map { $0.objectID }
        #expect(fa == fb)
        #expect(try Sample().writer.data() == forward)
    }

    @Test("Strings are byte-exact: canonically equivalent strings stay separate")
    func byteExactStrings() throws {
        var writer = FeatureStoreWriter(boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: "x")
        let composed = writer.intern("caf\u{00E9}")
        let decomposed = writer.intern("cafe\u{0301}")
        #expect(composed != decomposed)
        #expect(writer.intern("caf\u{00E9}") == composed)
        let cell = TileID(zoom: 13, x: 4_096, y: 4_096)!
        try writer.add(
            StoredFeature(classID: 0, kind: .point, objectType: .node, objectID: 1,
                tags: [StoredTag(key: composed, value: decomposed)],
                parts: [GeometryPart(points: [PackedPoint(longitude: 1, latitude: 1)])]), band: .detail, cell: cell)
        let file = try FeatureStoreFile(data: try writer.data())
        let tag = try #require(try file.features(in: cell, band: .detail).first?.tags.first)
        #expect(file.stringBytes(at: tag.key).map { Array($0) } == Array("caf\u{00E9}".utf8))
        #expect(file.stringBytes(at: tag.value).map { Array($0) } == Array("cafe\u{0301}".utf8))
        #expect(file.stringBytes(at: tag.key) != file.stringBytes(at: tag.value))
    }

    @Test("The most used string gets ID 0")
    func frequencyRenumbering() throws {
        var writer = FeatureStoreWriter(boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: "x")
        _ = writer.intern("rare")
        let common = writer.intern("common")
        let cell = TileID(zoom: 13, x: 4_096, y: 4_096)!
        try writer.add(
            StoredFeature(classID: 0, kind: .point, objectType: .node, objectID: 1,
                tags: [StoredTag(key: common, value: common)],
                parts: [GeometryPart(points: [PackedPoint(longitude: 1, latitude: 1)])]), band: .detail, cell: cell)
        let file = try FeatureStoreFile(data: try writer.data())
        #expect(file.string(at: 0) == "common" && file.string(at: 1) == "rare")
    }

    @Test("The writer rejects bad input")
    func invalidInput() throws {
        var writer = FeatureStoreWriter(boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: "x")
        let point = GeometryPart(points: [PackedPoint(longitude: 1, latitude: 1)])
        let feature = StoredFeature(classID: 0, kind: .point, objectType: .node, objectID: 1, parts: [point])
        #expect(throws: FeatureStoreError.self) { try writer.add(feature, band: .detail, cell: TileID(zoom: 12, x: 0, y: 0)!) }
        var badTag = feature
        badTag.tags = [StoredTag(key: 5, value: 6)]
        #expect(throws: FeatureStoreError.self) { try writer.add(badTag, band: .detail, cell: TileID(zoom: 13, x: 0, y: 0)!) }
        var far = feature
        far.parts = [GeometryPart(points: [PackedPoint(longitude: Int32.max, latitude: 0)])]
        try writer.add(far, band: .detail, cell: TileID(zoom: 13, x: 0, y: 0)!)
        #expect(throws: FeatureStoreError.self) { try writer.data() }
        var badRun = feature
        badRun.parts = [GeometryPart(points: [PackedPoint(longitude: 1, latitude: 1)], artificialEdges: [0..<1])]
        var second = FeatureStoreWriter(boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: "x")
        try second.add(badRun, band: .detail, cell: TileID(zoom: 13, x: 0, y: 0)!)
        #expect(throws: FeatureStoreError.self) { try second.data() }
        var relations = FeatureStoreWriter(boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: "x")
        try relations.add(StoredRelation(id: 1, tags: [], members: []))
        #expect(throws: FeatureStoreError.self) { try relations.add(StoredRelation(id: 1, tags: [], members: [])) }
    }

    @Test("An empty store round-trips")
    func emptyStore() throws {
        let writer = FeatureStoreWriter(boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: "")
        let file = try FeatureStoreFile(data: try writer.data())
        try file.verify()
        #expect(file.cellCount == 0 && file.bands.isEmpty && file.stringTableCount == 0)
    }

    @Test("A file opens from disk with memory mapping")
    func fromDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("featurestore-\(UUID().uuidString).gmk")
        defer { try? FileManager.default.removeItem(at: url) }
        let sample = try Sample()
        try sample.writer.write(to: url)
        let file = try FeatureStoreFile(contentsOf: url)
        try file.verify()
        #expect(try file.features(in: sample.cellA, band: .detail).count == 2)
    }

    @Test("A Data slice with a non-zero start index opens")
    func slicedData() throws {
        let bytes = try Sample().writer.data()
        let padded = Data([1, 2, 3]) + bytes
        let file = try FeatureStoreFile(data: padded.dropFirst(3))
        try file.verify()
    }
}
