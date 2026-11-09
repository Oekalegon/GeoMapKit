import FeatureStore
import Foundation
import GeoCore
import MapStyle
import Testing

@testable import MapRender

/// The names of lakes: at the point of the water that is farthest from the shore, only for water of some size, and not when the name
/// is far wider than the water.
@Suite("Water labels")
struct WaterLabelTests {
    private func rectangle(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [ScreenPoint] {
        [ScreenPoint(x: x0, y: y0), ScreenPoint(x: x1, y: y0), ScreenPoint(x: x1, y: y1), ScreenPoint(x: x0, y: y1), ScreenPoint(x: x0, y: y0)]
    }

    private func inside(_ p: ScreenPoint, _ ring: [ScreenPoint]) -> Bool {
        var result = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let a = ring[i], b = ring[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { result.toggle() }
            j = i
        }
        return result
    }

    // MARK: The point

    @Test func theMiddleOfARectangleIsItsPole() throws {
        let found = try #require(PolygonLabelPoint.find(in: [rectangle(0, 0, 100, 40)]))
        #expect(abs(found.point.y - 20) < 1.5 && found.distance > 18.5 && found.distance <= 20)
    }

    @Test func aBentLakeIsNamedInItsWaterAndNotAtTheCentreOfItsBox() throws {
        // An L: a long arm along the bottom and a long arm up the left side. The centre of the box (50, 50) is on land.
        let l = [
            ScreenPoint(x: 0, y: 0), ScreenPoint(x: 20, y: 0), ScreenPoint(x: 20, y: 80), ScreenPoint(x: 100, y: 80),
            ScreenPoint(x: 100, y: 100), ScreenPoint(x: 0, y: 100), ScreenPoint(x: 0, y: 0),
        ]
        #expect(!inside(ScreenPoint(x: 50, y: 50), l), "the centre of the bounding box is on land")
        let found = try #require(PolygonLabelPoint.find(in: [l]))
        #expect(inside(found.point, l) && found.distance >= 9)
    }

    @Test func anIslandIsNotWhereTheNameGoes() throws {
        // A lake with a big island in the middle: the name goes beside the island, in the water.
        let found = try #require(PolygonLabelPoint.find(in: [rectangle(0, 0, 100, 100), rectangle(30, 10, 70, 90)]))
        let lake = rectangle(0, 0, 100, 100), island = rectangle(30, 10, 70, 90)
        #expect(inside(found.point, lake) && !inside(found.point, island))
    }

    @Test func aPolygonWithNoAreaHasNoPoint() {
        #expect(PolygonLabelPoint.find(in: [[ScreenPoint(x: 0, y: 0), ScreenPoint(x: 10, y: 0), ScreenPoint(x: 20, y: 0), ScreenPoint(x: 0, y: 0)]]) == nil)
        #expect(PolygonLabelPoint.find(in: []) == nil)
    }

    @Test func aPolygonWithManyVerticesIsFoundInBoundedTime() throws {
        // A circle of 20,000 vertices: the search looks at a bounded number of squares.
        let ring = (0...20_000).map { i -> ScreenPoint in
            let a = Double(i) / 20_000 * 2 * .pi
            return ScreenPoint(x: 200 + 150 * cos(a), y: 200 + 150 * sin(a))
        }
        let started = ContinuousClock.now
        let found = try #require(PolygonLabelPoint.find(in: [ring]))
        #expect(abs(found.point.x - 200) < 5 && abs(found.point.y - 200) < 5 && found.distance > 140)
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    // MARK: The candidates of a scene

    /// A store with one named lake in one cell: a rectangle of the given size in degrees at the cell's centre.
    private func scene(width: Double, height: Double, zoom: Double) throws -> (MapScene, MapStyle) {
        var writer = FeatureStoreWriter(
            boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: "", classifierVersion: 20)
        let cell = TileID(zoom: 13, x: 4_400, y: 2_400)!
        let west = Int32((cell.northWest.longitude * 1e7).rounded()), east = Int32((cell.southEast.longitude * 1e7).rounded())
        let north = Int32((cell.northWest.latitude * 1e7).rounded()), south = Int32((cell.southEast.latitude * 1e7).rounded())
        let lon = west / 2 + east / 2, lat = north / 2 + south / 2
        let dx = Int32(width * 1e7 / 2), dy = Int32(height * 1e7 / 2)
        let ring = [
            PackedPoint(longitude: lon - dx, latitude: lat + dy), PackedPoint(longitude: lon + dx, latitude: lat + dy),
            PackedPoint(longitude: lon + dx, latitude: lat - dy), PackedPoint(longitude: lon - dx, latitude: lat - dy),
            PackedPoint(longitude: lon - dx, latitude: lat + dy),
        ]
        try writer.add(
            StoredFeature(
                classID: FeatureClass.waterArea.rawValue, kind: .area, objectType: .way, objectID: 77, nameID: writer.intern("Testsjön"),
                parts: [GeometryPart(points: ring)]),
            band: .detail, cell: cell)
        let file = try FeatureStoreFile(data: try writer.data())
        let centre = Coordinate(latitude: Double(lat) * 1e-7, longitude: Double(lon) * 1e-7)
        let viewport = MapViewport(center: centre, zoom: zoom, width: 400, height: 300)
        return (try MapSceneBuilder(file: file, style: .standard).scene(for: viewport), .standard)
    }

    @Test func aLakeIsNamedAtTheCentreOfItsWater() throws {
        // 0.01 degree is about 0.7 km east-west at 60 degrees: at zoom 14 about 40 points.
        let (scene, style) = try scene(width: 0.02, height: 0.008, zoom: 14)
        let candidates = LabelCandidates.collect(from: scene, style: style)
        let candidate = try #require(candidates.first { $0.objectID == 77 })
        #expect(candidate.text == "Testsjön" && abs(candidate.anchor.x - 200) < 3 && abs(candidate.anchor.y - 150) < 3)
        #expect(try #require(candidate.fitWidth) > 0)
    }

    @Test func aPondThatIsSmallOnTheScreenIsNotNamed() throws {
        // The same lake seen from far: a few points wide, under the minimum area of the style, and not named at zoom 9 at all.
        let (small, style) = try scene(width: 0.002, height: 0.001, zoom: 14)
        #expect(LabelCandidates.collect(from: small, style: style).allSatisfy { $0.objectID != 77 }, "about 15 points wide: a pond")
        let (far, _) = try scene(width: 0.02, height: 0.008, zoom: 9)
        #expect(LabelCandidates.collect(from: far, style: style).allSatisfy { $0.objectID != 77 }, "below the zoom of the label")
    }

    @Test func aNameFarWiderThanTheWaterIsNotPlaced() {
        let narrow = LabelCandidate(
            objectID: 1, text: "Testsjön", anchor: ScreenPoint(x: 100, y: 100), symbolRadius: 0, fontSize: 10,
            style: LabelStyle(size: ZoomValue(constant: 10), color: .black), fitWidth: 10)
        var roomy = narrow
        roomy.fitWidth = 40
        let measure: (String, Double) -> (width: Double, height: Double) = { _, _ in (50, 10) }
        #expect(LabelPlacer.place([narrow], viewWidth: 400, viewHeight: 300, measure: measure).isEmpty, "50 wide in 10 of water")
        #expect(LabelPlacer.place([roomy], viewWidth: 400, viewHeight: 300, measure: measure).count == 1, "50 wide in 40 of water: across")
        var plain = narrow
        plain.fitWidth = nil
        #expect(LabelPlacer.place([plain], viewWidth: 400, viewHeight: 300, measure: measure).count == 1, "other labels do not depend on it")
    }

    @Test func theMinimumAreaIsPartOfTheStyleFile() throws {
        let lake = try #require(MapStyle.standard.style(for: .waterArea)?.label)
        #expect(lake.minimumArea == 1_200)
        let json = try JSONEncoder().encode(lake)
        #expect(String(decoding: json, as: UTF8.self).contains("minimumArea"))
        #expect(try JSONDecoder().decode(LabelStyle.self, from: json) == lake)
        // A label without it writes no key, so older readers still read the file.
        let plain = LabelStyle(size: ZoomValue(constant: 10), color: .black)
        #expect(!String(decoding: try JSONEncoder().encode(plain), as: UTF8.self).contains("minimumArea"))
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(LabelStyle.self, from: Data(##"{"size": 10, "color": "#000000", "minimumArea": -1}"##.utf8))
        }
    }
}
