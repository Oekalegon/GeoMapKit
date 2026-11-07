import FeatureStore
import Foundation
import GeoCore
import MapStyle
import Testing

@testable import MapRender

@Suite("Bridges and tunnels in the scene")
struct MapSceneStructureTests {
    private let latitude: Int32 = 471_000_000

    /// A store with a road on the ground, a road bridge, a road tunnel and a path bridge (the standard style has no
    /// bridge style for sidewalks, so a pavement bridge is the case of a bridge drawn on the ground).
    private func scene() throws -> (MapScene, TileID) {
        var writer = FeatureStoreWriter(
            boundingBox: BoundingBox(south: 47.0, west: 9.4, north: 47.3, east: 9.7), attribution: "© OpenStreetMap contributors, ODbL")
        let cell = try #require(TileID.containing(Coordinate(latitude: 47.1, longitude: 9.5), zoom: 13))
        let west = Int32((cell.northWest.longitude * 1e7).rounded())
        func add(_ id: Int64, _ featureClass: FeatureClass, subclass: UInt8, dy: Int32) throws {
            let part = GeometryPart(points: [
                PackedPoint(longitude: west + 5_000, latitude: latitude + dy), PackedPoint(longitude: west + 9_000, latitude: latitude + dy),
            ])
            try writer.add(
                StoredFeature(classID: featureClass.rawValue, subclass: subclass, kind: .line, objectType: .way, objectID: id, parts: [part]),
                band: .detail, cell: cell)
        }
        try add(1, .roadMajor, subclass: 4, dy: 0)
        try add(2, .roadMajor, subclass: 4 | SubclassBits.bridge, dy: 300)
        try add(3, .roadMajor, subclass: 4 | SubclassBits.tunnel, dy: 600)
        try add(4, .pavement, subclass: 2 | SubclassBits.bridge, dy: 900)
        // A road on the ground that ends where the tunnel starts, and one that starts where the bridge ends.
        func addBefore(_ id: Int64, dy: Int32, from: Int32, to: Int32) throws {
            let part = GeometryPart(points: [PackedPoint(longitude: west + from, latitude: latitude + dy), PackedPoint(longitude: west + to, latitude: latitude + dy)])
            try writer.add(
                StoredFeature(classID: FeatureClass.roadMajor.rawValue, subclass: 4, kind: .line, objectType: .way, objectID: id, parts: [part]),
                band: .detail, cell: cell)
        }
        try addBefore(5, dy: 600, from: 1_000, to: 5_000)
        try addBefore(6, dy: 300, from: 9_000, to: 12_000)
        let file = try FeatureStoreFile(data: try writer.data())
        let centre = Coordinate(latitude: Double(latitude) / 1e7, longitude: Double(west + 7_000) / 1e7)
        let viewport = MapViewport(center: centre, zoom: 16, width: 400, height: 400)
        return (try MapSceneBuilder(file: file, style: .standard).scene(for: viewport), cell)
    }

    private func ids(_ scene: MapScene, _ featureClass: FeatureClass, _ part: DrawStep.Part, _ structure: Structure) -> [Int64] {
        scene.steps.filter { $0.step.featureClass == featureClass && $0.step.part == part && $0.step.structure == structure }
            .flatMap(\.lines).map(\.objectID).sorted()
    }

    @Test("Each line goes to the steps of its structure, and nowhere else")
    func linesGoToTheirOwnSteps() throws {
        let (scene, _) = try scene()
        // Lines 5 and 6 are roads on the ground that meet the tunnel and the bridge (see `portalEnds`).
        #expect(ids(scene, .roadMajor, .body, .ground) == [1, 5, 6])
        #expect(ids(scene, .roadMajor, .casing, .ground) == [1, 5, 6])
        #expect(ids(scene, .roadMajor, .body, .bridge) == [2])
        #expect(ids(scene, .roadMajor, .casing, .bridge) == [2])
        #expect(ids(scene, .roadMajor, .body, .tunnel) == [3])
        #expect(ids(scene, .roadMajor, .casing, .tunnel).isEmpty, "a tunnel has no casing step")
    }

    @Test("A road on the ground ends flat where a tunnel or a bridge starts, and keeps its round end elsewhere")
    func portalEnds() throws {
        let (scene, _) = try scene()
        func line(_ id: Int64) throws -> SceneLine { try #require(scene.steps.flatMap(\.lines).first { $0.objectID == id }) }
        #expect(try line(5).flatEnd && !line(5).flatStart, "ends where the tunnel starts")
        #expect(try line(6).flatStart && !line(6).flatEnd, "starts where the bridge ends")
        #expect(try !line(1).flatStart && !line(1).flatEnd, "a road that meets no bridge or tunnel is left alone")
        #expect(try !line(2).flatStart && !line(2).flatEnd && !line(3).flatStart && !line(3).flatEnd, "bridges and tunnels have flat ends already")
    }

    @Test("A bridge of a class without a bridge style is drawn on the ground")
    func unstyledBridgeIsOnTheGround() throws {
        let (scene, _) = try scene()
        #expect(ids(scene, .pavement, .body, .ground) == [4])
        #expect(ids(scene, .pavement, .body, .bridge).isEmpty)
        let line = try #require(scene.steps.flatMap(\.lines).first { $0.objectID == 4 })
        #expect(line.structure == .bridge, "the line still knows it is a bridge")
    }

    @Test("Bridge steps come after every ground step, and the tunnel before the ground road")
    func order() throws {
        let (scene, _) = try scene()
        let steps = scene.steps.map(\.step)
        let lastGround = try #require(steps.lastIndex { $0.structure == .ground })
        let firstBridge = try #require(steps.firstIndex { $0.structure == .bridge })
        #expect(firstBridge > lastGround)
        let tunnel = try #require(steps.firstIndex { $0.structure == .tunnel })
        let groundRoad = try #require(steps.firstIndex { $0.featureClass == .roadMajor && $0.structure == .ground })
        #expect(tunnel < groundRoad)
    }

    @Test("A road that ends at a vertex in the middle of another road ends flat; one that ends in the open stays round")
    func tJunctions() throws {
        var writer = FeatureStoreWriter(
            boundingBox: BoundingBox(south: 47.0, west: 9.4, north: 47.3, east: 9.7), attribution: "© OpenStreetMap contributors, ODbL")
        let cell = try #require(TileID.containing(Coordinate(latitude: 47.1, longitude: 9.5), zoom: 13))
        let west = Int32((cell.northWest.longitude * 1e7).rounded())
        func point(_ x: Int32, _ y: Int32) -> PackedPoint { PackedPoint(longitude: west + x, latitude: latitude + y) }
        func add(_ id: Int64, _ featureClass: FeatureClass, _ points: [PackedPoint]) throws {
            try writer.add(
                StoredFeature(classID: featureClass.rawValue, subclass: 4, kind: .line, objectType: .way, objectID: id, parts: [GeometryPart(points: points)]),
                band: .detail, cell: cell)
        }
        // A through road with a vertex at (6000, 0); a side road that ends there; a road that ends in the open;
        // a road whose end is the end of the through road (no T); and a path that ends at the vertex (paths keep round ends).
        try add(1, .roadMajor, [point(2_000, 0), point(6_000, 0), point(10_000, 0)])
        try add(2, .roadMinor, [point(6_000, 3_000), point(6_000, 0)])
        try add(3, .roadMinor, [point(2_000, 3_000), point(4_000, 3_000)])
        try add(4, .roadMinor, [point(10_000, 0), point(12_000, 2_000)])
        try add(5, .path, [point(6_000, -3_000), point(6_000, 0)])
        let file = try FeatureStoreFile(data: try writer.data())
        let centre = Coordinate(latitude: Double(latitude) / 1e7, longitude: Double(west + 6_000) / 1e7)
        let scene = try MapSceneBuilder(file: file, style: .standard).scene(for: MapViewport(center: centre, zoom: 16, width: 400, height: 400))
        func line(_ id: Int64) throws -> SceneLine { try #require(scene.steps.flatMap(\.lines).first { $0.objectID == id }) }
        #expect(try line(2).flatEnd && !line(2).flatStart, "the side road ends flat at the through road")
        #expect(try !line(1).flatStart && !line(1).flatEnd, "the through road is not changed")
        #expect(try !line(3).flatStart && !line(3).flatEnd, "a road that ends in the open keeps its round end")
        #expect(try !line(4).flatStart && !line(4).flatEnd, "the end of a road at the end of another is not a T junction")
        #expect(try !line(5).flatStart && !line(5).flatEnd, "paths keep their round ends")
    }

    @Test("Two roads of one class that continue each other with different lane counts blend to the mean width")
    func tapers() throws {
        var writer = FeatureStoreWriter(
            boundingBox: BoundingBox(south: 47.0, west: 9.4, north: 47.3, east: 9.7), attribution: "© OpenStreetMap contributors, ODbL")
        let cell = try #require(TileID.containing(Coordinate(latitude: 47.1, longitude: 9.5), zoom: 13))
        let west = Int32((cell.northWest.longitude * 1e7).rounded())
        func point(_ x: Int32, _ y: Int32) -> PackedPoint { PackedPoint(longitude: west + x, latitude: latitude + y) }
        func add(_ id: Int64, _ featureClass: FeatureClass, lanes: String?, _ points: [PackedPoint]) throws {
            let tags = lanes.map { [StoredTag(key: writer.intern("lanes"), value: writer.intern($0))] } ?? []
            try writer.add(
                StoredFeature(classID: featureClass.rawValue, subclass: 4, kind: .line, objectType: .way, objectID: id, tags: tags, parts: [GeometryPart(points: points)]),
                band: .detail, cell: cell)
        }
        try add(1, .roadMajor, lanes: "1", [point(2_000, 0), point(6_000, 0)])        // one lane, ends at the node
        try add(2, .roadMajor, lanes: "3", [point(6_000, 0), point(10_000, 0)])       // three lanes, starts there
        try add(3, .roadMajor, lanes: "2", [point(6_000, 0), point(6_000, 4_000)])    // a side road at a right angle
        try add(4, .roadMinor, lanes: "1", [point(12_000, 0), point(14_000, 0)])
        try add(5, .roadMinor, lanes: "1", [point(14_000, 0), point(16_000, 0)])      // same lanes: no blend
        try add(6, .roadMajor, lanes: "2", [point(16_000, 0), point(18_000, 0)])      // another class continues it: no blend
        let file = try FeatureStoreFile(data: try writer.data())
        let centre = Coordinate(latitude: Double(latitude) / 1e7, longitude: Double(west + 10_000) / 1e7)
        let view = MapViewport(center: centre, zoom: 18, width: 800, height: 400)
        let scene = try MapSceneBuilder(file: file, style: .standard).scene(for: view)
        func line(_ id: Int64) throws -> SceneLine { try #require(scene.steps.flatMap(\.lines).first { $0.objectID == id }) }
        let ground = try #require(MapStyle.standard.style(for: .roadMajor)?.stroke?.width)
        let one = ground.resolved(atZoom: 18, metresPerPoint: view.metresPerPoint, lanes: 1)
        let three = ground.resolved(atZoom: 18, metresPerPoint: view.metresPerPoint, lanes: 3)
        #expect(three - one > 5, "the lane counts give clearly different widths at this zoom")
        let mean = (one + three) / 2
        #expect(try abs((line(1).endWidth ?? 0) - mean) < 1e-9 && line(1).startWidth == nil)
        #expect(try abs((line(2).startWidth ?? 0) - mean) < 1e-9 && line(2).endWidth == nil)
        #expect(try line(3).startWidth == nil && line(3).endWidth == nil, "a side road is not a continuation")
        #expect(try line(4).endWidth == nil && line(5).startWidth == nil, "equal widths need no blend")
        #expect(try line(6).startWidth == nil, "a road of another class does not continue it")
    }
}
