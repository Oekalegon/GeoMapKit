import FeatureStore
import Foundation
import GeoCore
import Testing

@testable import FeatureStoreBuilder

/// A coarse level derived from the overview band of z13 cells: lines and areas that the clip cut apart are whole again.
@Suite("Level builder")
struct LevelBuilderTests {
    /// The zoom 8 block (4, 74) and cells of zoom 13 in it, at about 60 degrees north.
    private let block = TileID(zoom: 8, x: 4, y: 74)!
    private let baseColumn = 32 * 4 + 8
    private let baseRow = 32 * 74 + 8
    private var spec: LevelSpec { try! LevelSpec(topZoom: 8, classes: [FeatureClass.roadMajor.rawValue, FeatureClass.waterArea.rawValue]) }

    private func cell(_ dx: Int, _ dy: Int) -> TileID { TileID(zoom: 13, x: baseColumn + dx, y: baseRow + dy)! }

    private func writer() -> FeatureStoreWriter {
        FeatureStoreWriter(
            boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: "© OpenStreetMap contributors, ODbL",
            classifierVersion: 16)
    }

    private func pt(_ lon: Int32, _ lat: Int32) -> PackedPoint { PackedPoint(longitude: lon, latitude: lat) }

    private func road(
        _ id: Int64, _ points: [PackedPoint], before: Bool, after: Bool, in cell: TileID, to writer: inout FeatureStoreWriter
    ) throws {
        var flags: FeatureFlags = []
        if before { flags.insert(.continuesBefore) }
        if after { flags.insert(.continuesAfter) }
        try writer.add(
            StoredFeature(
                classID: FeatureClass.roadMajor.rawValue, kind: .line, objectType: .way, objectID: id, flags: flags,
                parts: [GeometryPart(points: points)]),
            band: .overview, cell: cell)
    }

    private func level(_ file: FeatureStoreWriter, spec: LevelSpec? = nil) throws -> (LevelResult?, FeatureStoreFile?) {
        let source = try FeatureStoreFile(data: try file.data())
        let result = try LevelBuilder.build(from: source, spec: spec ?? self.spec, tile: block, margin: 8)
        return (result, try result.map { try FeatureStoreFile(data: $0.data) })
    }

    @Test func aLineThatTheClipCutIntoThreeCellsIsOneLine() throws {
        var w = writer()
        let a = CellRect(tile: cell(0, 0)), b = CellRect(tile: cell(1, 0)), c = CellRect(tile: cell(2, 0))
        let lat = (a.north + a.south) / 2
        try road(1, [pt(a.west + 5_000, lat), pt(a.east, lat)], before: false, after: true, in: cell(0, 0), to: &w)
        try road(1, [pt(b.west, lat), pt(b.east, lat)], before: true, after: true, in: cell(1, 0), to: &w)
        try road(1, [pt(c.west, lat), pt(c.east - 5_000, lat)], before: true, after: false, in: cell(2, 0), to: &w)
        let (result, file) = try level(w)
        let report = try #require(result?.report)
        #expect(report.linesJoined == 2 && report.featuresRead == 3)
        let levelCell = try #require(TileID.containing(Coordinate(latitude: Double(lat) / 1e7, longitude: Double(a.west) / 1e7), zoom: 10))
        let features = try #require(file).features(in: levelCell, band: .overview)
        #expect(features.count == 1)
        // The three collinear pieces become one straight line of two vertices.
        #expect(features[0].parts[0].points.count == 2)
        #expect(file?.storageZoom == 10 && file?.bands == [.overview])
    }

    @Test func aLineWhoseHalvesAreEachTooSmallIsKeptWhenTheyAreJoined() throws {
        // 0.01 degree of longitude is less than three pixels at zoom 8 (0.0165 degree), two halves are more.
        var w = writer()
        let a = CellRect(tile: cell(0, 0)), b = CellRect(tile: cell(1, 0))
        let lat = (a.north + a.south) / 2
        try road(2, [pt(a.east - 100_000, lat), pt(a.east, lat)], before: false, after: true, in: cell(0, 0), to: &w)
        try road(2, [pt(b.west, lat), pt(b.west + 100_000, lat)], before: true, after: false, in: cell(1, 0), to: &w)
        let (result, _) = try level(w)
        #expect(result != nil && result?.report.droppedAsSmall == 0)

        var small = writer()
        try road(3, [pt(a.east - 100_000, lat), pt(a.east, lat)], before: false, after: false, in: cell(0, 0), to: &small)
        let (none, _) = try level(small)
        #expect(none == nil, "a line of 0.01 degree alone is left out")
    }

    @Test func classesOfTheLevelOnlyAreRead() throws {
        var w = writer()
        let a = CellRect(tile: cell(0, 0))
        let lat = (a.north + a.south) / 2
        try w.add(
            StoredFeature(
                classID: FeatureClass.path.rawValue, kind: .line, objectType: .way, objectID: 9,
                parts: [GeometryPart(points: [pt(a.west, lat), pt(a.east, lat)])]),
            band: .overview, cell: cell(0, 0))
        let (result, _) = try level(w)
        #expect(result == nil, "a path is not in the classes of the level")
    }

    /// The four quarters of a square around the common corner of four cells, as the clip cuts them.
    private func squareQuarters(into w: inout FeatureStoreWriter, skip: Set<Int> = []) throws -> (lon: Int32, lat: Int32) {
        let a = CellRect(tile: cell(0, 0)), d = CellRect(tile: cell(1, 1))
        let lonMid = a.east, latMid = a.south
        let dLon = Int32(Double(a.east - a.west) * 0.8), dLat = Int32(Double(a.north - a.south) * 0.8)
        func area(_ id: Int64, _ points: [PackedPoint], artificial: [Range<Int>], cell: TileID) throws {
            try w.add(
                StoredFeature(
                    classID: FeatureClass.waterArea.rawValue, kind: .area, objectType: .way, objectID: id,
                    parts: [GeometryPart(points: points, artificialEdges: artificial)]),
                band: .overview, cell: cell)
        }
        _ = d
        let nw = pt(lonMid - dLon, latMid + dLat), ne = pt(lonMid + dLon, latMid + dLat)
        let se = pt(lonMid + dLon, latMid - dLat), sw = pt(lonMid - dLon, latMid - dLat)
        if !skip.contains(0) {
            try area(7, [nw, pt(lonMid, latMid + dLat), pt(lonMid, latMid), pt(lonMid - dLon, latMid), nw], artificial: [1..<3], cell: cell(0, 0))
        }
        if !skip.contains(1) {
            try area(7, [pt(lonMid, latMid + dLat), ne, pt(lonMid + dLon, latMid), pt(lonMid, latMid), pt(lonMid, latMid + dLat)], artificial: [2..<4], cell: cell(1, 0))
        }
        if !skip.contains(2) {
            try area(7, [pt(lonMid, latMid), pt(lonMid, latMid - dLat), sw, pt(lonMid - dLon, latMid), pt(lonMid, latMid)], artificial: [0..<1, 3..<4], cell: cell(0, 1))
        }
        if !skip.contains(3) {
            try area(7, [pt(lonMid + dLon, latMid), se, pt(lonMid, latMid - dLat), pt(lonMid, latMid), pt(lonMid + dLon, latMid)], artificial: [2..<4], cell: cell(1, 1))
        }
        return (lonMid, latMid)
    }

    @Test func aSquareCutIntoFourQuartersIsOneRing() throws {
        var w = writer()
        let (lonMid, latMid) = try squareQuarters(into: &w)
        let (result, file) = try level(w)
        #expect(result?.report.openAreaChains == 0)
        let levelCell = try #require(TileID.containing(Coordinate(latitude: Double(latMid) / 1e7, longitude: Double(lonMid) / 1e7), zoom: 10))
        let features = try #require(file).features(in: levelCell, band: .overview)
        #expect(features.count == 1 && features[0].parts.count == 1)
        let ring = features[0].parts[0]
        // Four corners, closed. The simplifier keeps the first vertex of a ring, which is a point on a cell border here.
        #expect(ring.points.first == ring.points.last && Set(ring.points).count <= 5)
        let longitudes = Set(ring.points.map(\.longitude)), latitudes = Set(ring.points.map(\.latitude))
        #expect(longitudes.count == 2 && latitudes.count == 3 || longitudes.count == 3 && latitudes.count == 2 || (longitudes.count == 2 && latitudes.count == 2))
        #expect(ring.artificialEdges.isEmpty)
        #expect(!features[0].flags.contains(.incomplete))
    }

    @Test func aMissingQuarterLeavesAnOpenChainThatIsMarkedIncomplete() throws {
        var w = writer()
        // The north-east quarter is missing, but its cell exists (another feature lies in it): the edges that face it
        // are not an outer border, so the chains do not close.
        _ = try squareQuarters(into: &w, skip: [1])
        let b = CellRect(tile: cell(1, 0))
        try w.add(
            StoredFeature(
                classID: FeatureClass.roadMajor.rawValue, kind: .point, objectType: .node, objectID: 5,
                parts: [GeometryPart(points: [pt(b.west + 10, b.north - 10)])]),
            band: .overview, cell: cell(1, 0))
        let (result, file) = try level(w, spec: try LevelSpec(topZoom: 8, classes: [FeatureClass.waterArea.rawValue, FeatureClass.roadMajor.rawValue]))
        #expect(try #require(result).report.openAreaChains >= 1)
        let any = try #require(file)
        let flagged = try any.cells().flatMap { try any.features(in: $0, band: .overview) }.filter { $0.kind == .area }
        #expect(!flagged.isEmpty && flagged.allSatisfy { $0.flags.contains(.incomplete) })
    }

    @Test func aLevelHasOnlyTheCellsInsideItsBlock() throws {
        var w = writer()
        // A road in a cell of the neighbouring block (to the east of block 4) is read for the margin but not written.
        let outside = TileID(zoom: 13, x: 32 * 5 + 1, y: baseRow)!
        let o = CellRect(tile: outside)
        let lat = (o.north + o.south) / 2
        try road(4, [pt(o.west, lat), pt(o.east, lat)], before: false, after: false, in: outside, to: &w)
        let (result, _) = try level(w)
        #expect(result == nil)
    }

    @Test func invalidInputIsRefused() throws {
        #expect(throws: LevelError.invalidTopZoom(0)) { try LevelSpec(topZoom: 0, classes: []) }
        var w = writer()
        let a = CellRect(tile: cell(0, 0))
        try road(1, [pt(a.west, a.south), pt(a.east, a.south)], before: false, after: false, in: cell(0, 0), to: &w)
        let source = try FeatureStoreFile(data: try w.data())
        // A block finer than the cells of the level.
        #expect(throws: LevelError.self) { try LevelBuilder.build(from: source, spec: spec, tile: TileID(zoom: 12, x: 1, y: 1)!) }
    }

    @Test func aLevelFromTwoBlocksEqualsTheLevelFromOneFile() throws {
        // A road across the border between block (4, 74) and block (5, 74) whose halves are each too small alone.
        let west = TileID(zoom: 13, x: 32 * 4 + 31, y: 32 * 74 + 5)!, east = TileID(zoom: 13, x: 32 * 5, y: 32 * 74 + 5)!
        let w = CellRect(tile: west), e = CellRect(tile: east)
        let lat = (w.north + w.south) / 2
        var one = writer(), a = writer(), b = writer()
        try road(11, [pt(w.east - 100_000, lat), pt(w.east, lat)], before: false, after: true, in: west, to: &one)
        try road(11, [pt(e.west, lat), pt(e.west + 100_000, lat)], before: true, after: false, in: east, to: &one)
        try road(11, [pt(w.east - 100_000, lat), pt(w.east, lat)], before: false, after: true, in: west, to: &a)
        try road(11, [pt(e.west, lat), pt(e.west + 100_000, lat)], before: true, after: false, in: east, to: &b)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-level-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dataA = try a.data(), dataB = try b.data()
        try dataA.write(to: folder.appendingPathComponent("a.gmk"))
        try dataB.write(to: folder.appendingPathComponent("b.gmk"))
        let manifest = StoreManifest(
            formatVersion: try FeatureStoreFile(data: dataA).formatVersion, classifierVersion: 16, storageZoom: 13, blockZoom: 8,
            bands: [.overview], profile: "full", attribution: "© OpenStreetMap contributors, ODbL",
            blocks: [
                StoreManifest.Block(x: 4, y: 74, file: "a.gmk", bytes: Int64(dataA.count), builtAt: Date()),
                StoreManifest.Block(x: 5, y: 74, file: "b.gmk", bytes: Int64(dataB.count), builtAt: Date()),
            ])
        let set = try StoreSet(manifest: manifest, directory: folder)
        let fromSet = try LevelBuilder.build(
            from: set, spec: try LevelSpec(topZoom: 8, classes: [FeatureClass.roadMajor.rawValue]), tile: TileID(zoom: 8, x: 4, y: 74)!)
        let fromFile = try LevelBuilder.build(
            from: try FeatureStoreFile(data: try one.data()), spec: try LevelSpec(topZoom: 8, classes: [FeatureClass.roadMajor.rawValue]),
            tile: TileID(zoom: 8, x: 4, y: 74)!)
        #expect(fromSet != nil && fromSet?.data == fromFile?.data)
        #expect(fromSet?.report.linesJoined == 1)
    }
}
