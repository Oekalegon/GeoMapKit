import Foundation
import FeatureStore
import GeoCore
import MapStyle
import Testing

@testable import MapRender

/// A store with two neighbouring cells and a road, a path, a lake and a peak.
private struct World {
    var writer = FeatureStoreWriter(
        boundingBox: BoundingBox(south: 47.0, west: 9.4, north: 47.3, east: 9.7), attribution: "© OpenStreetMap contributors, ODbL")
    let cellA: TileID
    let cellB: TileID
    /// The border between the cells, in 1e-7 degrees.
    let borderLongitude: Int32
    let latitude: Int32 = 471_000_000

    init(laneTag: String? = "3") throws {
        let a = try #require(TileID.containing(Coordinate(latitude: 47.1, longitude: 9.5), zoom: 13))
        cellA = a
        cellB = try #require(TileID(zoom: 13, x: a.x + 1, y: a.y))
        borderLongitude = Int32((a.southEast.longitude * 1e7).rounded())
        let lanes = writer.intern("lanes")
        let tags = laneTag.map { [StoredTag(key: lanes, value: writer.intern($0))] } ?? []
        let name = writer.intern("Hauptstrasse")

        func line(_ x: [Int32], dy: [Int32]) -> GeometryPart {
            GeometryPart(points: zip(x, dy).map { PackedPoint(longitude: $0, latitude: latitude + $1) })
        }
        // A road that crosses the border; the clip point differs by one unit between the cells.
        try writer.add(
            StoredFeature(
                classID: FeatureClass.roadMajor.rawValue, kind: .line, objectType: .way, objectID: 100,
                flags: [.continuesAfter], nameID: name, tags: tags,
                parts: [line([borderLongitude - 2_000, borderLongitude], dy: [0, 0])]), band: .detail, cell: cellA)
        try writer.add(
            StoredFeature(
                classID: FeatureClass.roadMajor.rawValue, kind: .line, objectType: .way, objectID: 100,
                flags: [.continuesBefore], offsetAlongLine: 20_000, nameID: name, tags: tags,
                parts: [line([borderLongitude + 1, borderLongitude + 2_000], dy: [0, 0])]), band: .detail, cell: cellB)
        try writer.add(
            StoredFeature(
                classID: FeatureClass.path.rawValue, kind: .line, objectType: .way, objectID: 200,
                parts: [line([borderLongitude - 1_500, borderLongitude - 500], dy: [500, 800])]), band: .detail, cell: cellA)
        // A lake whose last edge lies on the cell border (artificial).
        let lake = GeometryPart(
            points: [
                PackedPoint(longitude: borderLongitude - 1_000, latitude: latitude - 1_000),
                PackedPoint(longitude: borderLongitude, latitude: latitude - 1_000),
                PackedPoint(longitude: borderLongitude, latitude: latitude - 500),
                PackedPoint(longitude: borderLongitude - 1_000, latitude: latitude - 500),
                PackedPoint(longitude: borderLongitude - 1_000, latitude: latitude - 1_000),
            ], artificialEdges: [1..<2])
        try writer.add(
            StoredFeature(classID: FeatureClass.waterArea.rawValue, kind: .area, objectType: .way, objectID: 300, parts: [lake]),
            band: .detail, cell: cellA)
        try writer.add(
            StoredFeature(
                classID: FeatureClass.peak.rawValue, kind: .point, objectType: .node, objectID: 400, nameID: name,
                parts: [GeometryPart(points: [PackedPoint(longitude: borderLongitude + 500, latitude: latitude + 300)])]),
            band: .detail, cell: cellB)
        // The same road in the mid band, one piece per cell.
        try writer.add(
            StoredFeature(
                classID: FeatureClass.roadMajor.rawValue, kind: .line, objectType: .way, objectID: 100, parts: [line([borderLongitude - 2_000, borderLongitude + 2_000], dy: [0, 0])]),
            band: .mid, cell: cellA)
    }

    func file() throws -> FeatureStoreFile { try FeatureStoreFile(data: try writer.data()) }

    func viewport(zoom: Double = 17) -> MapViewport {
        MapViewport(
            center: Coordinate(latitude: Double(latitude) * 1e-7, longitude: Double(borderLongitude) * 1e-7), zoom: zoom,
            width: 400, height: 400)
    }

    func scene(zoom: Double = 17, style: MapStyle = .standard) throws -> MapScene {
        try MapSceneBuilder(file: file(), style: style).scene(for: viewport(zoom: zoom))
    }
}

@Suite("MapScene")
struct MapSceneTests {
    @Test func roadPiecesAreJoinedAcrossTheCellBorder() throws {
        let scene = try World().scene()
        let road = try #require(scene.steps.first { $0.step == DrawStep(featureClass: .roadMajor, part: .body) })
        #expect(road.lines.count == 1)
        #expect(road.lines[0].points.count == 3)
        #expect(scene.cellCount == 2)
    }

    @Test func lanesAndNameComeFromTheTags() throws {
        let scene = try World(laneTag: "3").scene()
        let road = try #require(scene.steps.first { $0.step.featureClass == .roadMajor }?.lines.first)
        #expect(road.lanes == 3 && road.name == "Hauptstrasse")
    }

    @Test func missingOrBadLanesGiveNil() throws {
        for tag: String? in [nil, "two", "0", "-1"] {
            let scene = try World(laneTag: tag).scene()
            let road = try #require(scene.steps.first { $0.step.featureClass == .roadMajor }?.lines.first)
            #expect(road.lanes == nil, "tag \(tag ?? "nil")")
        }
    }

    @Test func casingStepsComeBeforeRoadBodies() throws {
        let steps = try World().scene().steps.map(\.step)
        let casing = try #require(steps.firstIndex(of: DrawStep(featureClass: .roadMajor, part: .casing)))
        let body = try #require(steps.firstIndex(of: DrawStep(featureClass: .roadMajor, part: .body)))
        #expect(casing < body)
    }

    @Test func areaOutlineLeavesOutTheBorderEdge() throws {
        let scene = try World().scene()
        let lake = try #require(scene.steps.first { $0.step.featureClass == .waterArea }?.areas.first)
        #expect(lake.rings.count == 1 && lake.rings[0].count == 5)
        // Four edges, one artificial: the other three form one run of 4 vertices.
        #expect(lake.outline.count == 1 && lake.outline[0].count == 4)
    }

    @Test func pointsAreProjected() throws {
        let scene = try World().scene()
        let peak = try #require(scene.steps.first { $0.step.featureClass == .peak }?.points.first)
        #expect(peak.position.x > 200 && peak.position.y < 200)
        #expect(peak.name == "Hauptstrasse")
    }

    @Test func classesHiddenAtThisZoomAreNotInTheScene() throws {
        // Paths start at zoom 12; at zoom 10 the mid band is read and only overview classes show.
        let scene = try World().scene(zoom: 10)
        #expect(!scene.steps.contains { $0.step.featureClass == .path })
    }

    @Test func lowZoomReadsTheMidBand() throws {
        let scene = try World().scene(zoom: 13)
        #expect(scene.band == .mid)
        let road = try #require(scene.steps.first { $0.step.featureClass == .roadMajor && $0.step.part == .body })
        #expect(road.lines.count == 1)
    }

    @Test func featuresOutsideTheViewAreCulled() throws {
        let world = try World()
        let far = MapViewport(center: Coordinate(latitude: 47.14, longitude: 9.52), zoom: 17, width: 300, height: 300)
        let scene = try MapSceneBuilder(file: world.file(), style: .standard).scene(for: far)
        #expect(scene.steps.isEmpty)
    }

    @Test func sameInputGivesTheSameScene() throws {
        let world = try World()
        #expect(try world.scene() == world.scene())
    }

    @Test func watchStyleLeavesOutClassesItDoesNotDraw() throws {
        let scene = try World().scene(style: .watch)
        let classes = Set(scene.steps.map(\.step.featureClass))
        #expect(classes.isSubset(of: Set(MapStyle.watch.classes.keys)))
        #expect(classes.contains(.roadMajor))
    }

    @Test func fileWithoutBandsThrows() throws {
        let writer = FeatureStoreWriter(
            boundingBox: BoundingBox(south: 47.0, west: 9.4, north: 47.3, east: 9.7), attribution: "x")
        let file = try FeatureStoreFile(data: try writer.data())
        let viewport = MapViewport(center: Coordinate(latitude: 47.1, longitude: 9.5), zoom: 15, width: 100, height: 100)
        #expect(throws: MapRenderError.noBands) { try MapSceneBuilder(file: file, style: .standard).scene(for: viewport) }
    }
}

@Suite("Ring outlines")
struct RingOutlineTests {
    private func ring(_ n: Int) -> [ScreenPoint] {
        let corners = [ScreenPoint(x: 0, y: 0), ScreenPoint(x: 1, y: 0), ScreenPoint(x: 1, y: 1), ScreenPoint(x: 0, y: 1)]
        return Array(corners.prefix(n)) + [corners[0]]
    }

    @Test func ringWithoutArtificialEdgesIsOneClosedRun() {
        let runs = MapSceneBuilder.realEdgeRuns(of: ring(4), artificial: [])
        #expect(runs.count == 1 && runs[0].count == 5)
    }

    @Test func artificialEdgeAtTheEndLeavesOneRun() {
        #expect(MapSceneBuilder.realEdgeRuns(of: ring(4), artificial: [3..<4]).map(\.count) == [4])
    }

    @Test func twoArtificialEdgesGiveTwoRuns() {
        #expect(MapSceneBuilder.realEdgeRuns(of: ring(4), artificial: [1..<2, 3..<4]).map(\.count) == [2, 2])
    }

    @Test func runsAcrossTheRingStartAreMerged() {
        // Edge 1 artificial: edges 2, 3, 0 are real and form one run that starts at vertex 2 and ends at vertex 1.
        let runs = MapSceneBuilder.realEdgeRuns(of: ring(4), artificial: [1..<2])
        #expect(runs.count == 1 && runs[0].count == 4)
    }

    @Test func outOfRangeArtificialRangesAreIgnored() {
        #expect(MapSceneBuilder.realEdgeRuns(of: ring(4), artificial: [10..<20]).count == 1)
    }

    @Test func degenerateRingsGiveNoRuns() {
        #expect(MapSceneBuilder.realEdgeRuns(of: [ScreenPoint(x: 0, y: 0)], artificial: []).isEmpty)
    }
}
