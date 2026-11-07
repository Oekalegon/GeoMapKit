import FeatureStore
import Testing

@testable import MapStyle

@Suite("MapStyle")
struct MapStyleTests {
    @Test func theCountryBorderIsTheBoundaryLineOnAWideSolidTransparentBand() throws {
        let border = try #require(MapStyle.standard.style(for: .countryBorder)?.stroke)
        let boundary = try #require(MapStyle.standard.style(for: .boundary)?.stroke)
        #expect(border.color == boundary.color && border.dash == boundary.dash, "the same dashed purple line")
        let casing = try #require(border.casing)
        #expect(casing.color.value(atZoom: 12).alpha < 1 && casing.color.value(atZoom: 12).alpha > 0)
        #expect(casing.extraPoints.value(atZoom: 12) >= 4, "much wider than the 1 point line")
        #expect(MapStyle.watch.style(for: .countryBorder) == nil)
        // The band is drawn before the line, so the line stays crisp on top of it.
        let steps = MapStyle.standard.drawSteps(atZoom: 12).filter { $0.featureClass == .countryBorder }
        #expect(steps.map(\.part) == [.casing, .body])
    }

    @Test func standardStyleCoversEveryClassExceptOther() {
        for featureClass in FeatureClass.allCases where featureClass != .other {
            #expect(MapStyle.standard.style(for: featureClass) != nil, "\(featureClass) has no standard style")
        }
        #expect(MapStyle.standard.style(for: .other) == nil)
    }

    @Test func watchStyleDrawsOnlyTheWatchProfile() {
        let watchClasses: Set<FeatureClass> = [
            .peak, .place, .poiAnchor, .path, .track, .roadMajor, .roadMinor, .railway, .waterLine, .waterArea,
            .forest, .landcover, .powerLine, .aerialway, .piste,
        ]
        #expect(Set(MapStyle.watch.classes.keys) == watchClasses)
    }

    @Test func watchStyleStartsAtTheMidBand() {
        for (featureClass, style) in MapStyle.watch.classes {
            #expect(style.visibleZoom.lowerBound >= 12, "\(featureClass) shows below the mid band")
        }
    }

    @Test func watchStyleHasNoDashesOrPointLabels() {
        for (featureClass, style) in MapStyle.watch.classes {
            #expect(style.stroke?.dash.isEmpty ?? true, "\(featureClass)")
            if featureClass != .place { #expect(style.label == nil, "\(featureClass)") }
        }
    }

    @Test func visibleClassesFollowZoomAndLayerOrder() {
        let low = MapStyle.standard.visibleClasses(atZoom: 9)
        #expect(low.contains(.forest) && low.contains(.waterArea) && low.contains(.place))
        #expect(!low.contains(.path) && !low.contains(.building))

        let high = MapStyle.standard.visibleClasses(atZoom: 17)
        #expect(high.contains(.building) && high.contains(.path) && high.contains(.tree))

        let layers = high.compactMap { MapStyle.standard.style(for: $0)?.layer }
        #expect(layers == layers.sorted())
    }

    @Test func visibleClassIDsAreRawValues() {
        let ids = MapStyle.standard.visibleClassIDs(atZoom: 16)
        #expect(ids.contains(FeatureClass.path.rawValue))
        #expect(!ids.contains(FeatureClass.other.rawValue))
    }

    @Test func trailsDrawAboveRoads() throws {
        let path = try #require(MapStyle.standard.style(for: .path)).layer
        let road = try #require(MapStyle.standard.style(for: .roadMajor)).layer
        #expect(path > road)
    }

    @Test func roadsWidenWithLanesInBothStyles() throws {
        for style in [MapStyle.standard, MapStyle.watch] {
            let width = try #require(style.style(for: .roadMajor)?.stroke?.width)
            let two = width.resolved(atZoom: 18, metresPerPoint: 0.25, lanes: 2)
            let four = width.resolved(atZoom: 18, metresPerPoint: 0.25, lanes: 4)
            #expect(four > two, "\(style.name)")
        }
    }

    @Test func pathsKeepTheirScreenWidth() throws {
        let width = try #require(MapStyle.standard.style(for: .path)?.stroke?.width)
        #expect(width.ground == nil)
    }

    @Test func noClassShowsBelowTheBandThatHoldsItsGeometry() {
        // Lowest bands from the rule table: detail starts at zoom 15, mid at zoom 12.
        let detailOnly: [FeatureClass] = [.building, .poi, .poiAnchor, .tree, .barrier, .transportStop, .roadPoint]
        let midOrHigher: [FeatureClass] = [.peak, .path, .track, .landcover, .landuseUrban, .piste, .powerLine, .aerialway]
        for style in [MapStyle.standard, MapStyle.watch] {
            for featureClass in detailOnly {
                if let lower = style.style(for: featureClass)?.visibleZoom.lowerBound {
                    #expect(lower >= 15, "\(style.name) \(featureClass)")
                }
            }
            for featureClass in midOrHigher {
                if let lower = style.style(for: featureClass)?.visibleZoom.lowerBound {
                    #expect(lower >= 12, "\(style.name) \(featureClass)")
                }
            }
        }
    }

    @Test func roadsHaveAnOutlineOnceZoomedIn() throws {
        for style in [MapStyle.standard, MapStyle.watch] {
            for roadClass in [FeatureClass.roadMajor, .roadMinor] {
                let casing = try #require(style.style(for: roadClass)?.stroke?.casing, "\(style.name) \(roadClass)")
                #expect(casing.extraPoints.value(atZoom: 18) > 0, "\(style.name) \(roadClass)")
                #expect(casing.extraPoints.value(atZoom: 8) <= 0.3, "\(style.name) \(roadClass)")
                let fill = try #require(style.style(for: roadClass)?.stroke?.color.value(atZoom: 18))
                #expect(casing.color.value(atZoom: 18) != fill, "casing must differ from the fill")
            }
        }
    }

    @Test func casingsOfRoadsComeBeforeEveryRoadFill() throws {
        for style in [MapStyle.standard, MapStyle.watch] {
            let steps = style.drawSteps(atZoom: 17)
            let minorCasing = try #require(steps.firstIndex(of: DrawStep(featureClass: .roadMinor, part: .casing)))
            let majorCasing = try #require(steps.firstIndex(of: DrawStep(featureClass: .roadMajor, part: .casing)))
            let minorBody = try #require(steps.firstIndex(of: DrawStep(featureClass: .roadMinor, part: .body)))
            let majorBody = try #require(steps.firstIndex(of: DrawStep(featureClass: .roadMajor, part: .body)))
            #expect(max(minorCasing, majorCasing) < min(minorBody, majorBody), "\(style.name)")
        }
    }

    @Test func classesWithoutCasingHaveOnlyABodyStep() {
        let steps = MapStyle.standard.drawSteps(atZoom: 17)
        #expect(steps.contains(DrawStep(featureClass: .path, part: .body)))
        #expect(!steps.contains(DrawStep(featureClass: .path, part: .casing)))
    }

    @Test func drawStepsAreDeterministicAndMatchVisibleClasses() {
        let steps = MapStyle.standard.drawSteps(atZoom: 15)
        #expect(steps == MapStyle.standard.drawSteps(atZoom: 15))
        let bodies = steps.filter { $0.part == .body }.map(\.featureClass)
        #expect(Set(bodies) == Set(MapStyle.standard.visibleClasses(atZoom: 15)))
    }

    @Test func casingWithoutCasingLayerSitsDirectlyUnderItsStroke() {
        let style = MapStyle(
            name: "T", background: .white,
            classes: [
                .path: ClassStyle(
                    stroke: StrokeStyle(
                        color: .color(0xFFFFFF), width: LineWidth(points: .constant(2)),
                        casing: .init(color: .color(0), extraPoints: .constant(1))),
                    layer: 5)
            ])
        #expect(style.drawSteps(atZoom: 10) == [
            DrawStep(featureClass: .path, part: .casing), DrawStep(featureClass: .path, part: .body),
        ])
    }
}
