import Foundation
import GeoCore
import Testing

@testable import FeatureStore

/// The cut of a Watch copy out of a bigger map.
@Suite("RegionCutter")
struct RegionCutterTests {
    private let cells = [
        TileID(zoom: 13, x: 4_300, y: 2_300)!, TileID(zoom: 13, x: 4_301, y: 2_300)!, TileID(zoom: 13, x: 4_320, y: 2_300)!,
    ]

    private func point(in cell: TileID, _ offset: Int32 = 1_000) -> PackedPoint {
        PackedPoint(
            longitude: Int32((cell.northWest.longitude * 1e7).rounded()) + offset,
            latitude: Int32((cell.northWest.latitude * 1e7).rounded()) - offset)
    }

    /// A source with, in every cell, a named peak and a path in the mid band, a building (not a Watch class) and a path in the
    /// overview band (not a Watch band); the peak carries a tag as well.
    private func makeSource() throws -> FeatureStoreFile {
        var writer = FeatureStoreWriter(
            boundingBox: BoundingBox(south: 59, west: 10, north: 60, east: 11), attribution: "© OpenStreetMap contributors, ODbL",
            classifierVersion: 20)
        for (number, cell) in cells.enumerated() {
            let name = writer.intern("Peak \(number)")
            let tag = StoredTag(key: writer.intern("ele"), value: writer.intern("\(number)"))
            func feature(_ classID: FeatureClass, kind: FeatureKind, id: Int64, name: UInt32? = nil, tags: [StoredTag] = []) -> StoredFeature {
                StoredFeature(
                    classID: classID.rawValue, kind: kind, objectType: .node, objectID: id, flags: [.continuesAfter], offsetAlongLine: 7,
                    nameID: name, tags: tags, parts: [GeometryPart(points: [point(in: cell), point(in: cell, 2_000)])])
            }
            try writer.add(feature(.peak, kind: .point, id: Int64(number), name: name, tags: [tag]), band: .mid, cell: cell)
            try writer.add(feature(.path, kind: .line, id: Int64(100 + number)), band: .mid, cell: cell)
            try writer.add(feature(.building, kind: .area, id: Int64(200 + number)), band: .detail, cell: cell)
            try writer.add(feature(.path, kind: .line, id: Int64(300 + number)), band: .overview, cell: cell)
        }
        return try FeatureStoreFile(data: writer.data())
    }

    private func output() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-cut-\(UUID().uuidString).gmk")
    }

    /// The area of the first two cells (a point inside each).
    private var twoCells: BoundingBox {
        let a = cells[0], b = cells[1]
        return BoundingBox(
            south: a.southEast.latitude + 0.0001, west: a.northWest.longitude + 0.0001, north: a.northWest.latitude - 0.0001,
            east: b.southEast.longitude - 0.0001)
    }

    @Test func theCopyHoldsTheCellsOfTheAreaWithTheClassesAndBandsOfTheProfile() throws {
        let url = output()
        defer { try? FileManager.default.removeItem(at: url) }
        let report = try RegionCutter(source: makeSource()).cut(area: twoCells, to: url)
        #expect(report.cellsExamined == 2 && report.cellsWritten == 2 && report.featuresWritten == 4)
        let copy = try FeatureStoreFile(contentsOf: url)
        try copy.verify()
        #expect(try copy.cells() == [cells[0], cells[1]], "the cell outside the area is not in the copy")
        #expect(copy.classifierVersion == 20 && copy.attribution == "© OpenStreetMap contributors, ODbL")
        #expect(copy.bands == [.mid])
        let mid = try copy.features(in: cells[0], band: .mid)
        #expect(Set(mid.map(\.classID)) == [FeatureClass.peak.rawValue, FeatureClass.path.rawValue])
        #expect(try copy.features(in: cells[0], band: .detail).isEmpty && copy.features(in: cells[0], band: .overview).isEmpty)
    }

    @Test func namesSurviveWithTheirOwnStringTableAndOtherTagsAreDropped() throws {
        let url = output()
        defer { try? FileManager.default.removeItem(at: url) }
        try RegionCutter(source: makeSource()).cut(area: twoCells, to: url)
        let copy = try FeatureStoreFile(contentsOf: url)
        let peak = try #require(copy.features(in: cells[1], band: .mid).first { $0.classID == FeatureClass.peak.rawValue })
        #expect(peak.nameID.flatMap { copy.string(at: $0) } == "Peak 1")
        #expect(peak.tags.isEmpty)
        #expect(copy.stringTableCount == 2, "only the two names that are used")
    }

    @Test func geometryFlagsAndOffsetsAreKeptExactly() throws {
        let source = try makeSource()
        let url = output()
        defer { try? FileManager.default.removeItem(at: url) }
        try RegionCutter(source: source).cut(area: twoCells, to: url)
        let copy = try FeatureStoreFile(contentsOf: url)
        let before = try source.features(in: cells[0], band: .mid).first { $0.classID == FeatureClass.path.rawValue }
        let after = try copy.features(in: cells[0], band: .mid).first { $0.classID == FeatureClass.path.rawValue }
        #expect(before != nil && before?.parts == after?.parts && before?.flags == after?.flags && before?.offsetAlongLine == after?.offsetAlongLine)
    }

    @Test func anAreaThatIsNotValidTooLargeOrEmptyIsRefused() throws {
        let cutter = RegionCutter(source: try makeSource(), maximumCells: 10)
        let url = output()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: RegionCutError.invalidArea) { try cutter.cut(area: BoundingBox(south: 60, west: 10, north: 59, east: 11), to: url) }
        #expect(throws: RegionCutError.invalidArea) { try cutter.cut(area: BoundingBox(south: 59, west: .nan, north: 60, east: 11), to: url) }
        #expect(throws: RegionCutError.self) { try cutter.cut(area: BoundingBox(south: 59, west: 10, north: 60, east: 11), to: url) }
        let empty = BoundingBox(south: 59.5, west: 12, north: 59.51, east: 12.01)
        #expect(throws: RegionCutError.emptyArea) { try cutter.cut(area: empty, to: url) }
        #expect(!FileManager.default.fileExists(atPath: url.path), "nothing is written for a refused cut")
    }
}
