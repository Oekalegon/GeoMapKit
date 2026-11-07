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
        #expect(casing.extraPoints.value(atZoom: 12) >= 3, "several times wider than the 1 point line")
        #expect(casing.extraPoints.value(atZoom: 8) < casing.extraPoints.value(atZoom: 16), "narrower when zoomed out")
        #expect(MapStyle.watch.style(for: .countryBorder) == nil)
        // The band is drawn before the line, so the line stays crisp on top of it.
        let steps = MapStyle.standard.drawSteps(atZoom: 12).filter { $0.featureClass == .countryBorder }
        #expect(steps.map(\.part) == [.casing, .body])
    }

    @Test func standardStyleCoversEveryClassExceptOtherAndAddresses() {
        for featureClass in FeatureClass.allCases where featureClass != .other && featureClass != .address {
            #expect(MapStyle.standard.style(for: featureClass) != nil, "\(featureClass) has no standard style")
        }
        #expect(MapStyle.standard.style(for: .other) == nil && MapStyle.standard.style(for: .address) == nil)
    }

    @Test func sidewalksAreFainterAndThinnerThanPaths() throws {
        let pavement = try #require(MapStyle.standard.style(for: .pavement))
        let path = try #require(MapStyle.standard.style(for: .path))
        let thinPavement = try #require(pavement.stroke?.width.points.value(atZoom: 16))
        let thinPath = try #require(path.stroke?.width.points.value(atZoom: 16))
        #expect(thinPavement < thinPath)
        #expect(pavement.visibleZoom.lowerBound > path.visibleZoom.lowerBound, "shown later than paths")
        #expect(pavement.layer < path.layer, "paths are drawn on top of sidewalks")
        #expect(MapStyle.watch.style(for: .pavement) == nil)
    }

    @Test func bridgesAreDrawnAfterEveryLineOnTheGroundAndTunnelsBeforeThem() throws {
        let steps = MapStyle.standard.drawSteps(atZoom: 16)
        func indices(_ matching: (DrawStep) -> Bool) -> [Int] { steps.indices.filter { matching(steps[$0]) } }
        let ground = indices { $0.structure == .ground }
        let bridges = indices { $0.structure == .bridge }
        let tunnels = indices { $0.structure == .tunnel }
        #expect(!bridges.isEmpty && !tunnels.isEmpty)
        #expect(try #require(bridges.min()) > (try #require(ground.max())), "every bridge step after every ground step")
        // Tunnels are above the area fills and below every line on the ground.
        let fills = indices { $0.structure == .ground && [.waterArea, .forest, .building, .landcover].contains($0.featureClass) }
        let groundLines = indices { $0.structure == .ground && [.roadMajor, .roadMinor, .path, .track, .railway].contains($0.featureClass) }
        #expect(try #require(tunnels.min()) > (try #require(fills.max())))
        #expect(try #require(tunnels.max()) < (try #require(groundLines.min())))
        // A bridge has its casing step before its body step, and all casings before the bodies of the same layer.
        let roadBridge = steps.filter { $0.featureClass == .roadMajor && $0.structure == .bridge }
        #expect(roadBridge.map(\.part) == [.casing, .body])
        // The Watch style draws bridges and tunnels like any other line.
        #expect(MapStyle.watch.drawSteps(atZoom: 16).allSatisfy { $0.structure == .ground })
    }

    @Test func aStyleWithoutBridgeOrTunnelStyleDrawsThemOnTheGround() throws {
        let pavement = try #require(MapStyle.standard.style(for: .pavement))
        #expect(pavement.drawnStructure(for: .bridge) == .ground && pavement.drawnStructure(for: .tunnel) == .ground)
        let road = try #require(MapStyle.standard.style(for: .roadMajor))
        #expect(road.drawnStructure(for: .bridge) == .bridge && road.drawnStructure(for: .tunnel) == .tunnel)
        #expect(road.drawnStructure(for: .ground) == .ground)
        // The water line has tunnels (culverts) but no bridges.
        let water = try #require(MapStyle.standard.style(for: .waterLine))
        #expect(water.drawnStructure(for: .tunnel) == .tunnel && water.drawnStructure(for: .bridge) == .ground)
    }

    @Test func aBridgeHasItsOwnCasingAndATunnelIsFainterAndHasNone() throws {
        let road = try #require(MapStyle.standard.style(for: .roadMinor))
        let ground = try #require(road.stroke(for: .ground))
        #expect(ground == road.stroke)
        let bridge = try #require(road.stroke(for: .bridge))
        #expect(bridge.casing == road.bridge?.casing && bridge.casing != ground.casing)
        #expect(bridge.color == ground.color && bridge.dash == ground.dash)
        #expect(ground.cap == .round && bridge.cap == .butt, "a bridge has flat ends, so its casing thickens only the sides")
        let tunnel = try #require(road.stroke(for: .tunnel))
        #expect(tunnel.casing == nil && tunnel.cap == .butt, "a road leaves a tunnel with a flat end")
        #expect(tunnel.color.value(atZoom: 16).alpha == ground.color.value(atZoom: 16).alpha * 0.5)
        #expect(tunnel.dash == [5, 3])
        // A railway tunnel keeps the dash of the railway when the style gives none of its own.
        let rail = try #require(MapStyle.standard.style(for: .railway))
        #expect(rail.stroke(for: .tunnel)?.dash == [2, 3])
        let plain = ClassStyle(stroke: .line(0, .constant(1), dash: [4, 4]), layer: 1, tunnel: TunnelStyle(opacity: 0.3))
        #expect(plain.stroke(for: .tunnel)?.dash == [4, 4])
        #expect(ClassStyle(layer: 1, bridge: nil).stroke(for: .bridge) == nil)
        #expect(TunnelStyle(opacity: 7).opacity == 1 && TunnelStyle(opacity: -1).opacity == 0)
    }

    @Test func railwaysAreSolidLinesAndRailTunnelsAreDashed() throws {
        let rail = try #require(MapStyle.standard.style(for: .railway))
        #expect(rail.stroke?.dash.isEmpty == true, "a railway is a solid line")
        #expect(rail.stroke(for: .tunnel)?.dash == [2, 3], "a railway tunnel is dashed, so it still stands out")
        #expect(MapStyle.watch.style(for: .railway)?.stroke?.dash.isEmpty == true)
    }

    @Test func aRoadAreaIsFilledAndDrawnUnderTheRoads() throws {
        let area = try #require(MapStyle.standard.style(for: .roadArea))
        #expect(area.fill != nil, "a surface, filled")
        let casingLayer = try #require(MapStyle.standard.style(for: .roadMinor)?.casingLayer)
        #expect(area.layer < casingLayer, "under every road casing")
        let building = try #require(MapStyle.standard.style(for: .building))
        let landcover = try #require(MapStyle.standard.style(for: .landcover))
        #expect(area.layer < building.layer && area.layer > landcover.layer, "over the land cover, under the buildings")
        #expect(MapStyle.watch.style(for: .roadArea) == nil)
    }

    @Test func aSubclassByteTellsTheStructure() {
        #expect(Structure(subclass: 4) == .ground)
        #expect(Structure(subclass: 4 | SubclassBits.bridge) == .bridge)
        #expect(Structure(subclass: 4 | SubclassBits.tunnel) == .tunnel)
        #expect(Structure(subclass: SubclassBits.bridge | SubclassBits.tunnel) == .tunnel)
    }

    @Test func watchStyleDrawsOnlyTheWatchProfile() {
        let watchClasses: Set<FeatureClass> = [
            .peak, .place, .poiAnchor, .path, .track, .roadMajor, .roadMinor, .railway, .waterLine, .waterArea,
            .forest, .landcover, .powerLine, .aerialway, .piste, .sea,
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
