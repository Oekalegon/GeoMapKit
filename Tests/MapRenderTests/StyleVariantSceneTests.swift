import FeatureStore
import GeoCore
import MapStyle
import Testing

@testable import MapRender

/// A variant of a class is its own step, with its own look; the features of the class that are in no variant stay in the class's step.
@Suite("Style variants in the scene")
struct StyleVariantSceneTests {
    private func style(_ variants: [StyleVariant]) -> MapStyle {
        var road = ClassStyle(stroke: StrokeStyle(color: ZoomValue(constant: MapColor(hex: 0xFFA000)), width: LineWidth(points: ZoomValue(constant: 4))), layer: 20)
        road.variants = variants
        return MapStyle(name: "T", background: .white, classes: [.roadMajor: road])
    }

    @Test func aVariantIsItsOwnDrawStepOnItsOwnLayer() {
        let motorway = StyleVariant(name: "M", subclasses: ["motorway"], layer: 30)
        let steps = style([motorway]).drawSteps(atZoom: 12)
        #expect(steps.map(\.variant) == [nil, 0])
        #expect(steps.map(\.featureClass) == [.roadMajor, .roadMajor])
    }

    @Test func aVariantThatShowsFromAnEarlierZoomKeepsItsClassInTheList() {
        var road = ClassStyle(stroke: StrokeStyle(color: ZoomValue(constant: MapColor(hex: 0xFFA000)), width: LineWidth(points: ZoomValue(constant: 4))), visibleZoom: 10...24, layer: 20)
        road.variants = [StyleVariant(name: "M", subclasses: ["motorway"], visibleZoom: 5...24)]
        let style = MapStyle(name: "T", background: .white, classes: [.roadMajor: road])
        #expect(style.visibleClasses(atZoom: 6) == [.roadMajor])
        #expect(style.drawSteps(atZoom: 6).map(\.variant) == [0], "the class's own step is hidden at zoom 6")
        #expect(style.drawSteps(atZoom: 12).map(\.variant) == [nil, 0])
    }

    @Test func theStyleOfAStepIsTheVariantsLook() {
        let red = StrokeStyle(color: ZoomValue(constant: MapColor(hex: 0xE53935)), width: LineWidth(points: ZoomValue(constant: 6)))
        let s = style([StyleVariant(name: "M", subclasses: ["motorway"], stroke: red)])
        let steps = s.drawSteps(atZoom: 12)
        #expect(s.style(for: steps[0])?.stroke?.width != red.width)
        #expect(s.style(for: steps[1])?.stroke == red)
        #expect(s.style(for: .roadMajor, variant: 5) == nil)
    }

    @Test func theStandardStyleHasVariantsForMotorwaysAndFarmland() {
        let road = MapStyle.standard.classes[.roadMajor]?.variants.first
        #expect(road?.subclasses.contains("motorway") == true)
        #expect(MapStyle.standard.classes[.landcover]?.variants.first?.subclasses == ["farmland"])
        #expect(MapStyle.standard.drawSteps(atZoom: 12).contains { $0.featureClass == .roadMajor && $0.variant == 0 })
    }

    @Test func aStyleWithoutVariantsHasTheSameStepsAsBefore() {
        for zoom in [3.0, 9, 12, 15] {
            #expect(MapStyle.watch.drawSteps(atZoom: zoom).allSatisfy { $0.variant == nil })
        }
    }

    /// A store with a motorway (id 1), a secondary road (id 2) and a farmland area (id 3), and a rail with gauge 1000 (id 4) in the detail band.
    private func scene(style: MapStyle, band: ZoomBand = .detail, zoom: Double = 16) throws -> MapScene {
        var writer = FeatureStoreWriter(
            boundingBox: BoundingBox(south: 47.0, west: 9.4, north: 47.3, east: 9.7), attribution: "© OpenStreetMap contributors, ODbL")
        let cell = try #require(TileID.containing(Coordinate(latitude: 47.1, longitude: 9.5), zoom: 13))
        let west = Int32((cell.northWest.longitude * 1e7).rounded())
        func line(_ id: Int64, _ featureClass: FeatureClass, subclass: UInt8, dy: Int32, tags: [StoredTag] = []) throws {
            let part = GeometryPart(points: [
                PackedPoint(longitude: west + 5_000, latitude: 471_000_000 + dy), PackedPoint(longitude: west + 9_000, latitude: 471_000_000 + dy),
            ])
            try writer.add(
                StoredFeature(classID: featureClass.rawValue, subclass: subclass, kind: .line, objectType: .way, objectID: id, tags: band == .detail ? tags : [], parts: [part]),
                band: band, cell: cell)
        }
        try line(1, .roadMajor, subclass: SubclassNames.numbers(of: "motorway", in: .roadMajor)[0], dy: 0)
        try line(2, .roadMajor, subclass: SubclassNames.numbers(of: "secondary", in: .roadMajor)[0], dy: 300)
        let gauge = [StoredTag(key: writer.intern("gauge"), value: writer.intern("1000"))]
        try line(4, .railway, subclass: SubclassNames.numbers(of: "rail", in: .railway)[0], dy: 900, tags: gauge)
        let ring = [
            PackedPoint(longitude: west + 5_000, latitude: 471_002_000), PackedPoint(longitude: west + 9_000, latitude: 471_002_000),
            PackedPoint(longitude: west + 9_000, latitude: 471_004_000), PackedPoint(longitude: west + 5_000, latitude: 471_004_000),
            PackedPoint(longitude: west + 5_000, latitude: 471_002_000),
        ]
        try writer.add(
            StoredFeature(classID: FeatureClass.landcover.rawValue, subclass: SubclassNames.numbers(of: "farmland", in: .landcover)[0], kind: .area, objectType: .way, objectID: 3, parts: [GeometryPart(points: ring)]),
            band: band, cell: cell)
        let file = try FeatureStoreFile(data: try writer.data())
        let centre = Coordinate(latitude: 47.1, longitude: Double(west + 7_000) / 1e7)
        return try MapSceneBuilder(file: file, style: style).scene(for: MapViewport(center: centre, zoom: zoom, width: 400, height: 400))
    }

    private func ids(_ scene: MapScene, _ featureClass: FeatureClass, variant: Int?) -> [Int64] {
        scene.steps.filter { $0.step.featureClass == featureClass && $0.step.variant == variant && $0.step.part == .body }
            .flatMap { $0.lines.map(\.objectID) + $0.areas.map(\.objectID) }.sorted()
    }

    @Test func aMotorwayAndASecondaryRoadLandInDifferentSteps() throws {
        var style = MapStyle.standard
        style.classes[.roadMajor]?.variants = [StyleVariant(name: "Motorways", subclasses: ["motorway"], layer: 30)]
        let scene = try scene(style: style)
        #expect(ids(scene, .roadMajor, variant: 0) == [1])
        #expect(ids(scene, .roadMajor, variant: nil) == [2])
    }

    @Test func farmlandIsDrawnWithItsOwnFillAndTheRestOfTheLandCoverKeepsTheClasses() throws {
        var style = MapStyle.standard
        style.classes[.landcover]?.variants = [StyleVariant(name: "Farmland", subclasses: ["farmland"], fill: FillStyle(color: ZoomValue(constant: MapColor(hex: 0xFFEB3B))))]
        let scene = try scene(style: style)
        #expect(ids(scene, .landcover, variant: 0) == [3])
        #expect(ids(scene, .landcover, variant: nil).isEmpty)
    }

    @Test func aTagConditionSelectsInTheDetailBandAndNeverInABandWithoutTheTag() throws {
        var style = MapStyle.standard
        style.classes[.railway]?.variants = [StyleVariant(name: "Metre gauge", tags: [TagCondition(key: "gauge", values: ["1000"])], layer: 40)]
        #expect(ids(try scene(style: style), .railway, variant: 0) == [4])
        let mid = try scene(style: style, band: .mid, zoom: 13)
        #expect(ids(mid, .railway, variant: 0).isEmpty && ids(mid, .railway, variant: nil) == [4])
    }
}

