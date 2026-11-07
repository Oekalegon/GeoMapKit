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
        #expect(ids(scene, .roadMajor, .body, .ground) == [1])
        #expect(ids(scene, .roadMajor, .casing, .ground) == [1])
        #expect(ids(scene, .roadMajor, .body, .bridge) == [2])
        #expect(ids(scene, .roadMajor, .casing, .bridge) == [2])
        #expect(ids(scene, .roadMajor, .body, .tunnel) == [3])
        #expect(ids(scene, .roadMajor, .casing, .tunnel).isEmpty, "a tunnel has no casing step")
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
}
