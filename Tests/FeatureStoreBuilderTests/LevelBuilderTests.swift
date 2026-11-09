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
    private func squareQuarters(into w: inout FeatureStoreWriter, skip: Set<Int> = []) throws -> (lon: Int32, lat: Int32, dLon: Int32, dLat: Int32) {
        let a = CellRect(tile: cell(0, 0))
        let lonMid = a.east, latMid = a.south
        let dLon = Int32(Double(a.east - a.west) * 0.8), dLat = Int32(Double(a.north - a.south) * 0.8)
        func area(_ id: Int64, _ points: [PackedPoint], artificial: [Range<Int>], cell: TileID) throws {
            try w.add(
                StoredFeature(
                    classID: FeatureClass.waterArea.rawValue, kind: .area, objectType: .way, objectID: id,
                    parts: [GeometryPart(points: points, artificialEdges: artificial)]),
                band: .overview, cell: cell)
        }
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
        return (lonMid, latMid, dLon, dLat)
    }

    /// A water area that is a rectangle in one cell, with the outline as a `waterEdge` line of the same feature.
    private func waterRectangle(
        _ id: Int64, halfWidth: Int32, halfHeight: Int32, in cell: TileID, to w: inout FeatureStoreWriter
    ) throws {
        let rect = CellRect(tile: cell)
        let lon = rect.west + (rect.east - rect.west) / 2, lat = rect.south + (rect.north - rect.south) / 2
        let ring = [
            pt(lon - halfWidth, lat - halfHeight), pt(lon + halfWidth, lat - halfHeight), pt(lon + halfWidth, lat + halfHeight),
            pt(lon - halfWidth, lat + halfHeight), pt(lon - halfWidth, lat - halfHeight),
        ]
        try w.add(
            StoredFeature(
                classID: FeatureClass.waterArea.rawValue, kind: .area, objectType: .way, objectID: id,
                parts: [GeometryPart(points: ring)]),
            band: .overview, cell: cell)
        try w.add(
            StoredFeature(
                classID: FeatureClass.waterEdge.rawValue, kind: .line, objectType: .way, objectID: id,
                parts: [GeometryPart(points: ring)]),
            band: .overview, cell: cell)
    }

    private func levelFeatures(_ file: FeatureStoreFile?, classID: FeatureClass) throws -> [StoredFeature] {
        let file = try #require(file)
        var found: [StoredFeature] = []
        for cell in (0..<4).flatMap({ dx in (0..<4).map { dy in TileID(zoom: 10, x: (baseColumn / 8) + dx - 1, y: (baseRow / 8) + dy - 1)! } }) {
            found += try file.features(in: cell, band: .overview, classes: [classID.rawValue])
        }
        return found
    }

    @Test func aDitchThatIsKilometresLongIsLeftOutOfALevelWithItsOutlineAndALakeStays() throws {
        var w = writer()
        let cellWidth = CellRect(tile: cell(0, 0)).east - CellRect(tile: cell(0, 0)).west
        let cellHeight = CellRect(tile: cell(0, 0)).north - CellRect(tile: cell(0, 0)).south
        // Level 8: a pixel is 0.0014 degree of longitude × 2^5 ... a ditch of 2 cells long and 0.002 of a cell high is far
        // under half a pixel wide but its box is far over three pixels; the lake is a third of a cell on each side.
        try waterRectangle(1, halfWidth: cellWidth / 2 - 10, halfHeight: cellHeight / 1000, in: cell(0, 0), to: &w)
        try waterRectangle(2, halfWidth: cellWidth / 3, halfHeight: cellHeight / 3, in: cell(1, 0), to: &w)
        let spec = try LevelSpec(
            topZoom: 8, classes: [FeatureClass.waterArea.rawValue, FeatureClass.waterEdge.rawValue])
        let (result, file) = try level(w, spec: spec)
        let areas = try levelFeatures(file, classID: .waterArea)
        let edges = try levelFeatures(file, classID: .waterEdge)
        #expect(areas.map(\.objectID) == [2], "the ditch is not a surface at this zoom")
        #expect(edges.map(\.objectID) == [2], "and its outline goes with it")
        #expect((result?.report.droppedAsSmall ?? 0) >= 2)
    }

    @Test func aPondIsLeftOutOfALevel() throws {
        var w = writer()
        let cellWidth = CellRect(tile: cell(0, 0)).east - CellRect(tile: cell(0, 0)).west
        // Square, so it is not thin: a tenth of a cell (about 0.4 pixel at level 8) on a side is a pond.
        try waterRectangle(3, halfWidth: cellWidth / 20, halfHeight: cellWidth / 40, in: cell(0, 0), to: &w)
        let spec = try LevelSpec(topZoom: 8, classes: [FeatureClass.waterArea.rawValue, FeatureClass.waterEdge.rawValue])
        let (result, _) = try level(w, spec: spec)
        #expect(result == nil)
    }

    @Test func aSquareCutIntoFourQuartersIsOneRing() throws {
        var w = writer()
        let (lonMid, latMid, dLon, dLat) = try squareQuarters(into: &w)
        let (result, file) = try level(w)
        #expect(result?.report.openAreaChains == 0)
        let levelCell = try #require(TileID.containing(Coordinate(latitude: Double(latMid) / 1e7, longitude: Double(lonMid) / 1e7), zoom: 10))
        let features = try #require(file).features(in: levelCell, band: .overview)
        #expect(features.count == 1 && features[0].parts.count == 1)
        let ring = features[0].parts[0]
        // Four corners, closed. The simplifier keeps the first vertex of a ring, which is a point on a cell border here.
        #expect(ring.points.first == ring.points.last && Set(ring.points).count <= 5)
        #expect(ring.points.map(\.longitude).min() == lonMid - dLon && ring.points.map(\.longitude).max() == lonMid + dLon)
        #expect(ring.points.map(\.latitude).min() == latMid - dLat && ring.points.map(\.latitude).max() == latMid + dLat)
        #expect(ring.artificialEdges.isEmpty)
        #expect(!features[0].flags.contains(.incomplete))
    }

    @Test func aQuarterThatIsMissingFromACellThatHoldsNothingElseOfTheFeatureLeavesTheRingClosed() throws {
        var w = writer()
        // The north-east quarter is missing and its cell holds a road only: nothing of the area is there, so the edges that face it
        // stay and the three quarters make one closed ring.
        _ = try squareQuarters(into: &w, skip: [1])
        let b = CellRect(tile: cell(1, 0))
        try w.add(
            StoredFeature(
                classID: FeatureClass.roadMajor.rawValue, kind: .point, objectType: .node, objectID: 5,
                parts: [GeometryPart(points: [pt(b.west + 10, b.north - 10)])]),
            band: .overview, cell: cell(1, 0))
        let (result, file) = try level(w, spec: try LevelSpec(topZoom: 8, classes: [FeatureClass.waterArea.rawValue, FeatureClass.roadMajor.rawValue]))
        #expect(try #require(result).report.openAreaChains == 0)
        let level = try #require(file)
        let areas = try level.cells().flatMap { try level.features(in: $0, band: .overview) }.filter { $0.kind == .area }
        #expect(!areas.isEmpty && areas.allSatisfy { !$0.flags.contains(.incomplete) })
    }

    @Test func aChainThatCannotCloseIsWrittenApartAsAnIncompleteFeatureAndTheRestKeepsItsFill() throws {
        var w = writer()
        // The north-east quarter is missing, but its cell holds a small ring of the same feature far from the border: that cell has
        // a piece of the feature, so the edges that face it are taken to have a twin there, and the chain stays open.
        _ = try squareQuarters(into: &w, skip: [1])
        let b = CellRect(tile: cell(1, 0))
        let lon = b.west / 2 + b.east / 2, lat = b.north / 2 + b.south / 2, d: Int32 = 100_000
        try w.add(
            StoredFeature(
                classID: FeatureClass.waterArea.rawValue, kind: .area, objectType: .way, objectID: 7,
                parts: [GeometryPart(points: [pt(lon - d, lat + d), pt(lon + d, lat + d), pt(lon + d, lat - d), pt(lon - d, lat - d), pt(lon - d, lat + d)])]),
            band: .overview, cell: cell(1, 0))
        let (result, file) = try level(w)
        #expect(try #require(result).report.openAreaChains == 1)
        let level = try #require(file)
        let areas = try level.cells().flatMap { try level.features(in: $0, band: .overview) }.filter { $0.kind == .area }
        #expect(areas.contains { $0.flags.contains(.incomplete) }, "the open chain is drawn as an outline")
        #expect(areas.contains { !$0.flags.contains(.incomplete) }, "the small ring that closed keeps its fill")
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

        // A road that crosses the border of the block is cut at it: nothing of it is written east of the border.
        var crossing = writer()
        let west = TileID(zoom: 13, x: 32 * 4 + 31, y: baseRow)!, east = TileID(zoom: 13, x: 32 * 5, y: baseRow)!
        let a = CellRect(tile: west), b = CellRect(tile: east)
        let latitude = (a.north + a.south) / 2
        try road(5, [pt(a.east - 200_000, latitude), pt(a.east, latitude)], before: false, after: true, in: west, to: &crossing)
        try road(5, [pt(b.west, latitude), pt(b.west + 200_000, latitude)], before: true, after: false, in: east, to: &crossing)
        let (_, file) = try level(crossing)
        let written = try #require(file)
        let cells = try written.cells()
        #expect(cells.count == 1 && cells.allSatisfy { $0.x < 32 * 5 / 8 })
        let line = try #require(try written.features(in: cells[0], band: .overview).first)
        #expect(line.parts[0].points.last?.longitude == a.east, "cut exactly at the border of the block")
        #expect(line.flags.contains(.continuesAfter), "the line goes on in the next block")
    }

    @Test func aPolygonWithAHoleKeepsBothRings() throws {
        var w = writer()
        let a = CellRect(tile: cell(2, 2))
        let lonMid = a.west / 2 + a.east / 2, latMid = a.north / 2 + a.south / 2
        let outer = Int32(Double(a.east - a.west) * 0.45), inner = Int32(Double(a.east - a.west) * 0.2)
        func square(_ d: Int32) -> [PackedPoint] {
            [pt(lonMid - d, latMid + d), pt(lonMid + d, latMid + d), pt(lonMid + d, latMid - d), pt(lonMid - d, latMid - d), pt(lonMid - d, latMid + d)]
        }
        try w.add(
            StoredFeature(
                classID: FeatureClass.waterArea.rawValue, kind: .area, objectType: .relation, objectID: 8,
                parts: [GeometryPart(points: square(outer)), GeometryPart(points: square(inner))]),
            band: .overview, cell: cell(2, 2))
        let (result, file) = try level(w)
        #expect(result?.report.openAreaChains == 0)
        let built = try #require(file)
        let features = try built.cells().flatMap { try built.features(in: $0, band: .overview) }
        #expect(features.count == 1 && features[0].parts.count == 2, "the outer ring and the hole")
    }

    @Test func anAreaAtTheEdgeOfTheDataIsClosedByItsOwnBorderEdges() throws {
        var w = writer()
        // Only the north-west quarter exists: its artificial edges face cells that are not in the source, so they stay.
        _ = try squareQuarters(into: &w, skip: [1, 2, 3])
        let (result, file) = try level(w)
        #expect(result?.report.openAreaChains == 0)
        #expect(try #require(file).cells().count == 1)
    }

    @Test func invalidInputIsRefused() throws {
        #expect(throws: LevelError.invalidTopZoom(0)) { try LevelSpec(topZoom: 0, classes: []) }
        var w = writer()
        let a = CellRect(tile: cell(0, 0))
        try road(1, [pt(a.west, a.south), pt(a.east, a.south)], before: false, after: false, in: cell(0, 0), to: &w)
        let source = try FeatureStoreFile(data: try w.data())
        // A block finer than the cells of the level.
        #expect(throws: LevelError.self) { try LevelBuilder.build(from: source, spec: spec, tile: TileID(zoom: 12, x: 1, y: 1)!) }
        #expect(throws: LevelError.self) { try LevelBuilder.build(from: source, spec: spec, tile: block, margin: -1) }
        // A block of zoom 0 would read the whole world.
        #expect(throws: LevelError.self) { try LevelBuilder.build(from: source, spec: spec, tile: TileID(zoom: 0, x: 0, y: 0)!) }
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

    @Test func twoNeighbouringLevelBlocksMeetOnTheirBorder() throws {
        // A long line with a bump close to the border, cut into cells by the builder's own splitter. With a small margin the two
        // blocks read different parts of it, so a simplification before the cut would give them different crossing points.
        let west = TileID(zoom: 13, x: 32 * 4 + 31, y: 32 * 74 + 5)!
        let w = CellRect(tile: west)
        let lat = (w.north + w.south) / 2
        let width = w.east - w.west
        let line = [
            pt(w.east - 12 * width, lat), pt(w.east - 3 * width, lat + 4_000), pt(w.east - width / 3, lat - 9_000),
            pt(w.east + width / 3, lat + 9_000), pt(w.east + 3 * width, lat - 4_000), pt(w.east + 12 * width, lat),
        ]
        var source = writer()
        for (cell, piece) in CellSplitter.split(line: line, zoom: 13) {
            try source.add(
                StoredFeature(
                    classID: FeatureClass.roadMajor.rawValue, kind: .line, objectType: .way, objectID: 21, flags: piece.flags,
                    offsetAlongLine: piece.offsetCentimetres, parts: [GeometryPart(points: piece.points)]),
                band: .overview, cell: cell)
        }
        let file = try FeatureStoreFile(data: try source.data())
        let spec = try LevelSpec(topZoom: 8, classes: [FeatureClass.roadMajor.rawValue])
        func crossing(_ tile: TileID, last: Bool) throws -> PackedPoint {
            let result = try #require(try LevelBuilder.build(from: file, spec: spec, tile: tile, margin: 4))
            let built = try FeatureStoreFile(data: result.data)
            let cells = try built.cells().sorted { $0.x < $1.x }
            let cell = try #require(last ? cells.last : cells.first)
            let feature = try #require(try built.features(in: cell, band: .overview).first)
            return try #require(last ? feature.parts[0].points.last : feature.parts[0].points.first)
        }
        let left = try crossing(TileID(zoom: 8, x: 4, y: 74)!, last: true)
        let right = try crossing(TileID(zoom: 8, x: 5, y: 74)!, last: false)
        #expect(left == right, "the line crosses the border of the blocks at the same point in both")
        #expect(left.longitude == w.east)
    }

    @Test func anAreaCutByTheBorderOfTwoLevelBlocksMeetsOnIt() throws {
        // A rectangle across the border between block (4, 74) and block (5, 74), cut by the clip into a west and an east piece whose
        // edges along the border of the cells are artificial.
        let west = TileID(zoom: 13, x: 32 * 4 + 31, y: 32 * 74 + 5)!, east = TileID(zoom: 13, x: 32 * 5, y: 32 * 74 + 5)!
        let w = CellRect(tile: west)
        let border = w.east
        let lat = w.north / 2 + w.south / 2
        let halfWidth: Int32 = 120_000, halfHeight: Int32 = 100_000
        var source = writer()
        func area(_ points: [PackedPoint], artificial: Range<Int>, in cell: TileID) throws {
            try source.add(
                StoredFeature(
                    classID: FeatureClass.waterArea.rawValue, kind: .area, objectType: .way, objectID: 31,
                    parts: [GeometryPart(points: points, artificialEdges: [artificial])]),
                band: .overview, cell: cell)
        }
        // West piece, clockwise from the north-west corner: the edge down the border is edge 1 (north-east corner to south-east corner).
        let nw = pt(border - halfWidth, lat + halfHeight), ne = pt(border, lat + halfHeight)
        let se = pt(border, lat - halfHeight), sw = pt(border - halfWidth, lat - halfHeight)
        try area([nw, ne, se, sw, nw], artificial: 1..<2, in: west)
        let nw2 = pt(border, lat + halfHeight), ne2 = pt(border + halfWidth, lat + halfHeight)
        let se2 = pt(border + halfWidth, lat - halfHeight), sw2 = pt(border, lat - halfHeight)
        try area([nw2, ne2, se2, sw2, nw2], artificial: 3..<4, in: east)
        let file = try FeatureStoreFile(data: try source.data())
        let spec = try LevelSpec(topZoom: 8, classes: [FeatureClass.waterArea.rawValue])

        func borderPoints(_ tile: TileID) throws -> (points: Set<PackedPoint>, artificial: Bool) {
            let result = try #require(try LevelBuilder.build(from: file, spec: spec, tile: tile, margin: 4))
            let built = try FeatureStoreFile(data: result.data)
            var points = Set<PackedPoint>()
            var artificial = false
            for cell in try built.cells() {
                for feature in try built.features(in: cell, band: .overview) {
                    for part in feature.parts {
                        for (index, point) in part.points.enumerated() where point.longitude == border {
                            points.insert(point)
                            if index + 1 < part.points.count, part.points[index + 1].longitude == border,
                                part.artificialEdges.contains(where: { $0.contains(index) })
                            { artificial = true }
                        }
                    }
                }
            }
            return (points, artificial)
        }
        let left = try borderPoints(TileID(zoom: 8, x: 4, y: 74)!), right = try borderPoints(TileID(zoom: 8, x: 5, y: 74)!)
        #expect(left.points == right.points && left.points.count == 2, "the corners on the border are the same in both blocks")
        #expect(left.artificial && right.artificial, "the edge along the border of the blocks is marked artificial on both sides")
    }

    @Test func aRingWhosePiecesMissEachOtherAlongTheBorderIsStillOneRing() throws {
        // The two pieces of a rectangle across the border between two blocks, but the east piece is 0.02 degree further north
        // along the border: two blocks that simplified a coastline that runs along the border differently. The ends do not meet; each
        // is on the same line of the border as the start it should join.
        let west = TileID(zoom: 13, x: 32 * 4 + 31, y: 32 * 74 + 5)!, east = TileID(zoom: 13, x: 32 * 5, y: 32 * 74 + 5)!
        let w = CellRect(tile: west)
        let border = w.east
        let lat = w.north / 2 + w.south / 2
        let halfWidth: Int32 = 120_000, halfHeight: Int32 = 80_000, shift: Int32 = 200_000
        var source = writer()
        func area(_ points: [PackedPoint], artificial: Range<Int>, in cell: TileID) throws {
            try source.add(
                StoredFeature(
                    classID: FeatureClass.waterArea.rawValue, kind: .area, objectType: .way, objectID: 32,
                    parts: [GeometryPart(points: points, artificialEdges: [artificial])]),
                band: .overview, cell: cell)
        }
        let nw = pt(border - halfWidth, lat + halfHeight), ne = pt(border, lat + halfHeight)
        let se = pt(border, lat - halfHeight), sw = pt(border - halfWidth, lat - halfHeight)
        try area([nw, ne, se, sw, nw], artificial: 1..<2, in: west)
        let nw2 = pt(border, lat + halfHeight + shift), ne2 = pt(border + halfWidth, lat + halfHeight + shift)
        let se2 = pt(border + halfWidth, lat - halfHeight + shift), sw2 = pt(border, lat - halfHeight + shift)
        try area([nw2, ne2, se2, sw2, nw2], artificial: 3..<4, in: east)
        let file = try FeatureStoreFile(data: try source.data())
        let spec = try LevelSpec(topZoom: 8, classes: [FeatureClass.waterArea.rawValue])
        let result = try #require(try LevelBuilder.build(from: file, spec: spec, tile: TileID(zoom: 8, x: 4, y: 74)!, margin: 4))
        #expect(result.report.openAreaChains == 0, "the ends were joined along the border")
        let built = try FeatureStoreFile(data: result.data)
        let features = try built.cells().flatMap { try built.features(in: $0, band: .overview) }
        #expect(!features.isEmpty && features.allSatisfy { !$0.flags.contains(.incomplete) })
    }
}
