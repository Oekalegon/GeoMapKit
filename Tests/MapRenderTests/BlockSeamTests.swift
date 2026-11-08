import Foundation
import FeatureStore
import GeoCore
import MapStyle
import Testing

@testable import MapRender

/// A map made of two block files must look exactly like the same map made of one file: a line, an area and a name that cross the
/// border between the blocks are joined like those that cross a border between two cells.
@Suite("Blocks across a seam")
struct BlockSeamTests {
    /// The cells on both sides of a block border of the zoom 8 grid.
    private let west = TileID(zoom: 13, x: 32 * 4 + 31, y: 32 * 74 + 5)!
    private let east = TileID(zoom: 13, x: 32 * 5, y: 32 * 74 + 5)!
    private let latitude: Int32

    init() {
        // The middle of the cell's height, at about 60 degrees north.
        let cell = TileID(zoom: 13, x: 32 * 5, y: 32 * 74 + 5)!
        latitude = Int32(((cell.northWest.latitude + cell.southEast.latitude) / 2 * 1e7).rounded())
    }

    private var border: Int32 { Int32((east.northWest.longitude * 1e7).rounded()) }

    private func writer() -> FeatureStoreWriter {
        FeatureStoreWriter(
            boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: "© OpenStreetMap contributors, ODbL",
            classifierVersion: 16)
    }

    private func line(_ xs: [Int32]) -> GeometryPart { GeometryPart(points: xs.map { PackedPoint(longitude: $0, latitude: latitude) }) }

    /// The road, the lake and the peak of the test, each piece in the cell it belongs to. A block file or the single file gets
    /// the cells it is given.
    private func fill(_ writer: inout FeatureStoreWriter, cells: [TileID]) throws {
        let name = writer.intern("Grensevei"), lanes = writer.intern("lanes"), three = writer.intern("3")
        let tags = [StoredTag(key: lanes, value: three)]
        for band in [ZoomBand.mid, .detail] {
            if cells.contains(west) {
                try writer.add(
                    StoredFeature(
                        classID: FeatureClass.roadMajor.rawValue, kind: .line, objectType: .way, objectID: 100, flags: [.continuesAfter],
                        nameID: name, tags: tags, parts: [line([border - 3_000, border])]), band: band, cell: west)
                let lake = GeometryPart(
                    points: [
                        PackedPoint(longitude: border - 1_500, latitude: latitude + 800), PackedPoint(longitude: border, latitude: latitude + 800),
                        PackedPoint(longitude: border, latitude: latitude + 1_500), PackedPoint(longitude: border - 1_500, latitude: latitude + 1_500),
                        PackedPoint(longitude: border - 1_500, latitude: latitude + 800),
                    ], artificialEdges: [1..<2])
                try writer.add(
                    StoredFeature(classID: FeatureClass.waterArea.rawValue, kind: .area, objectType: .way, objectID: 300, parts: [lake]),
                    band: band, cell: west)
            }
            if cells.contains(east) {
                try writer.add(
                    StoredFeature(
                        classID: FeatureClass.roadMajor.rawValue, kind: .line, objectType: .way, objectID: 100, flags: [.continuesBefore],
                        offsetAlongLine: 30_000, nameID: name, tags: tags, parts: [line([border, border + 3_000])]), band: band, cell: east)
                let lake = GeometryPart(
                    points: [
                        PackedPoint(longitude: border, latitude: latitude + 800), PackedPoint(longitude: border + 1_000, latitude: latitude + 800),
                        PackedPoint(longitude: border + 1_000, latitude: latitude + 1_500), PackedPoint(longitude: border, latitude: latitude + 1_500),
                        PackedPoint(longitude: border, latitude: latitude + 800),
                    ], artificialEdges: [3..<4])
                try writer.add(
                    StoredFeature(classID: FeatureClass.waterArea.rawValue, kind: .area, objectType: .way, objectID: 300, parts: [lake]),
                    band: band, cell: east)
                try writer.add(
                    StoredFeature(
                        classID: FeatureClass.peak.rawValue, kind: .point, objectType: .node, objectID: 400, nameID: writer.intern("Grensetoppen"),
                        parts: [GeometryPart(points: [PackedPoint(longitude: border + 500, latitude: latitude - 300)])]), band: band, cell: east)
            }
        }
    }

    private func viewport(zoom: Double) -> MapViewport {
        MapViewport(
            center: Coordinate(latitude: Double(latitude) * 1e-7, longitude: Double(border) * 1e-7), zoom: zoom, width: 400, height: 400)
    }

    /// The same cells as one file, and as two block files in a manifest.
    private func sources() throws -> (single: FeatureStoreFile, set: StoreSet, folder: URL) {
        var all = writer()
        try fill(&all, cells: [west, east])
        let single = try FeatureStoreFile(data: try all.data())

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-seam-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var a = writer(), b = writer()
        // Another string in the west block, so that the numbers of the same names differ between the blocks.
        try a.add(
            StoredFeature(
                classID: FeatureClass.peak.rawValue, kind: .point, objectType: .node, objectID: 1, nameID: a.intern("0 elsewhere"),
                parts: [GeometryPart(points: [PackedPoint(longitude: border - 200_000, latitude: latitude)])]),
            band: .detail, cell: west)
        try fill(&a, cells: [west])
        try fill(&b, cells: [east])
        try a.data().write(to: folder.appendingPathComponent("west.gmk"))
        try b.data().write(to: folder.appendingPathComponent("east.gmk"))
        let manifest = StoreManifest(
            formatVersion: single.formatVersion, classifierVersion: 16, storageZoom: 13, blockZoom: 8, bands: [.mid, .detail], profile: "full",
            attribution: "© OpenStreetMap contributors, ODbL",
            blocks: [
                StoreManifest.Block(x: 4, y: 74, file: "west.gmk", bytes: Int64(try a.data().count), builtAt: Date(timeIntervalSince1970: 1_800_000_000)),
                StoreManifest.Block(x: 5, y: 74, file: "east.gmk", bytes: Int64(try b.data().count), builtAt: Date(timeIntervalSince1970: 1_800_000_000)),
            ])
        return (single, try StoreSet(manifest: manifest, directory: folder), folder)
    }

    @Test("The scene of two blocks is the scene of one file, at the detail zoom and at the mid zoom")
    func sameScene() throws {
        let (single, set, folder) = try sources()
        defer { try? FileManager.default.removeItem(at: folder) }
        for zoom in [17.0, 14.0] {
            let one = try MapSceneBuilder(file: single, style: .standard).scene(for: viewport(zoom: zoom))
            let two = try MapSceneBuilder(source: set, style: .standard).scene(for: viewport(zoom: zoom))
            #expect(one == two, "zoom \(zoom)")
            #expect(one.cellCount == 2)
        }
    }

    @Test("The road is one line across the seam, with its name and lanes from the files it came from")
    func joined() throws {
        let (_, set, folder) = try sources()
        defer { try? FileManager.default.removeItem(at: folder) }
        let scene = try MapSceneBuilder(source: set, style: .standard).scene(for: viewport(zoom: 17))
        let road = try #require(scene.steps.first { $0.step == DrawStep(featureClass: .roadMajor, part: .body) })
        #expect(road.lines.count == 1 && road.lines[0].points.count == 3, "one line of three points, not two pieces")
        #expect(road.lines[0].name == "Grensevei" && road.lines[0].lanes == 3)
        let peak = try #require(scene.steps.first { $0.step.featureClass == .peak }?.points.first)
        #expect(peak.name == "Grensetoppen")
        #expect(scene.attribution == "© OpenStreetMap contributors, ODbL")
    }

    @Test("A set whose block file is missing fails the scene with the reason, and a view outside the blocks is empty")
    func failures() throws {
        let (_, set, folder) = try sources()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.removeItem(at: folder.appendingPathComponent("east.gmk"))
        #expect(throws: StoreSetError.blockMissing("east.gmk")) { try MapSceneBuilder(source: set, style: .standard).scene(for: viewport(zoom: 17)) }
        let faraway = MapViewport(center: Coordinate(latitude: 10, longitude: 10), zoom: 17, width: 400, height: 400)
        #expect(try MapSceneBuilder(source: set, style: .standard).scene(for: faraway).cellCount == 0)
    }
}
