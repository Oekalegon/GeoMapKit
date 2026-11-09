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

    /// The same cells as two block files of the zoom 8 grid (cells 0 and 1 in one, cell 2 in the other), each with its own string table.
    private func makeSet(version: [UInt16] = [20, 20]) throws -> (set: StoreSet, folder: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-cutset-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var blocks: [StoreManifest.Block] = []
        for (index, group) in [[0, 1], [2]].enumerated() {
            var writer = FeatureStoreWriter(
                boundingBox: BoundingBox(south: 59, west: 10, north: 60, east: 11), attribution: "© OpenStreetMap contributors, ODbL",
                classifierVersion: version[index])
            // A string that only this block has, so that the numbers of a name differ between the blocks.
            _ = writer.intern("only in block \(index)")
            for number in group {
                let cell = cells[number]
                try writer.add(
                    StoredFeature(
                        classID: FeatureClass.peak.rawValue, kind: .point, objectType: .node, objectID: Int64(number),
                        nameID: writer.intern("Peak \(number)"), parts: [GeometryPart(points: [point(in: cell)])]),
                    band: .mid, cell: cell)
            }
            let data = try writer.data()
            let name = "block\(index).gmk"
            try data.write(to: folder.appendingPathComponent(name))
            blocks.append(
                StoreManifest.Block(
                    x: index == 0 ? 134 : 135, y: 71, file: name, bytes: Int64(data.count), builtAt: Date(timeIntervalSince1970: 1_800_000_000)))
        }
        let manifest = StoreManifest(
            formatVersion: Int(FileHeader.formatVersion), classifierVersion: Int(version[0]), storageZoom: 13, blockZoom: 8, bands: [.mid],
            profile: "full", attribution: "© OpenStreetMap contributors, ODbL", blocks: blocks)
        return (try StoreSet(manifest: manifest, directory: folder), folder)
    }

    @Test func aSetOfBlocksIsCutToOneFileWithOneStringTable() throws {
        let (set, folder) = try makeSet()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = output()
        defer { try? FileManager.default.removeItem(at: url) }
        let area = BoundingBox(
            south: cells[2].southEast.latitude + 0.0001, west: cells[0].northWest.longitude + 0.0001, north: cells[0].northWest.latitude - 0.0001,
            east: cells[2].southEast.longitude - 0.0001)
        let report = try RegionCutter(source: set).cut(area: area, to: url, sourceDate: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(report.cellsExamined == 21 && report.cellsWritten == 3)
        let copy = try FeatureStoreFile(contentsOf: url)
        try copy.verify()
        #expect(copy.sourceDate == Date(timeIntervalSince1970: 1_800_000_000))
        for number in 0..<3 {
            let peak = try #require(copy.features(in: cells[number], band: .mid).first)
            #expect(peak.nameID.flatMap { copy.string(at: $0) } == "Peak \(number)", "the name of a block's feature is read from that block")
        }
        #expect(copy.stringTableCount == 3, "the strings that only a block has are not in the copy")
    }

    @Test func filesWithDifferentClassTablesAreNotMixed() throws {
        let (set, folder) = try makeSet(version: [20, 19])
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = output()
        let area = BoundingBox(
            south: cells[2].southEast.latitude + 0.0001, west: cells[0].northWest.longitude + 0.0001, north: cells[0].northWest.latitude - 0.0001,
            east: cells[2].southEast.longitude - 0.0001)
        #expect(throws: RegionCutError.self) { try RegionCutter(source: set).cut(area: area, to: url) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aFolderThatIsNotThereIsAnIOError() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-folder-\(UUID().uuidString)/copy.gmk")
        do {
            try RegionCutter(source: makeSource()).cut(area: twoCells, to: url)
            Issue.record("expected an error")
        } catch let error as RegionCutError {
            guard case .io = error else { Issue.record("expected io, got \(error)"); return }
        }
    }

    @Test func anAreaOnTheBorderOfCellsTakesTheCellsItTouches() throws {
        // From a corner of a cell to the corner of the next: points on borders fall in one of the two cells, so only the count of
        // cells in each direction is certain (one or two), never zero.
        let a = cells[0], b = cells[1]
        let box = BoundingBox(
            south: a.southEast.latitude, west: a.northWest.longitude, north: a.northWest.latitude, east: b.southEast.longitude)
        let range = try RegionCutter(source: makeSource()).cells(of: box)
        #expect((1...2).contains(range.rows.count) && (2...3).contains(range.columns.count))
        #expect(range.columns.contains(a.x) && range.columns.contains(b.x) && range.rows.contains(a.y))
    }

    @Test func aSquareOfTheSameSideIsMoreCellsInTheNorth() throws {
        // Cells are square on the map and shrink with the cosine of the latitude, so a square of the same side in kilometres is about 8 times as
        // many cells at 70 degrees north as at the equator: the limit in cells is a smaller area in the north.
        var writer = FeatureStoreWriter(boundingBox: BoundingBox(south: -1, west: -1, north: 71, east: 1), attribution: "x")
        try writer.add(
            StoredFeature(classID: 1, kind: .point, objectType: .node, objectID: 1, parts: [GeometryPart(points: [PackedPoint(longitude: 0, latitude: 0)])]),
            band: .mid, cell: TileID(zoom: 13, x: 4_096, y: 4_096)!)
        let cutter = RegionCutter(source: try FeatureStoreFile(data: writer.data()), maximumCells: 100_000)
        func cells(at latitude: Double) throws -> Int {
            let half = 10.0 / 2 / 111.32
            let range = try cutter.cells(of: BoundingBox(
                south: latitude - half, west: 10 - half / cos(latitude * .pi / 180), north: latitude + half, east: 10 + half / cos(latitude * .pi / 180)))
            return range.columns.count * range.rows.count
        }
        let equator = try cells(at: 0), north = try cells(at: 70)
        #expect(north > 4 * equator, "\(equator) cells at the equator and \(north) at 70 degrees north")
    }
}
