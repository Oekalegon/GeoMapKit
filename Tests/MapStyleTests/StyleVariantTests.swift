import FeatureStore
import Foundation
import Testing

@testable import MapStyle

/// Different looks for some of the features of a class: by subclass name and by tag.
@Suite("Style variants")
struct StyleVariantTests {
    private let red = FillStyle(color: .color(0xFF0000))
    private let motorway = StyleVariant(
        name: "Motorways", subclasses: ["motorway", "trunk"], stroke: StrokeStyle(color: .color(0xE53935), width: LineWidth(points: .constant(6))), layer: 30)
    private func road(_ variants: [StyleVariant]) -> ClassStyle {
        var style = ClassStyle(stroke: StrokeStyle(color: .color(0xFFA000), width: LineWidth(points: .constant(4))), layer: 20)
        style.variants = variants
        return style
    }

    @Test func aMotorwayGetsTheVariantAndAPrimaryRoadKeepsTheClass() {
        let style = road([motorway])
        let motorwayNumber = SubclassNames.numbers(of: "motorway", in: .roadMajor)[0]
        let primaryNumber = SubclassNames.numbers(of: "primary", in: .roadMajor)[0]
        let onMotorway = style.resolved(subclass: motorwayNumber, in: .roadMajor)
        #expect(onMotorway.layer == 30 && onMotorway.stroke == motorway.stroke && onMotorway.variants.isEmpty)
        #expect(style.resolved(subclass: primaryNumber, in: .roadMajor) == style)
    }

    @Test func theBridgeAndTunnelBitsDoNotHideTheSubclass() {
        let style = road([motorway])
        let number = SubclassNames.numbers(of: "motorway", in: .roadMajor)[0]
        #expect(style.variantIndex(subclass: number | SubclassBits.bridge, in: .roadMajor) == 0)
        #expect(style.variantIndex(subclass: number | SubclassBits.tunnel, in: .roadMajor) == 0)
    }

    @Test func theFirstMatchingVariantWins() {
        let all = StyleVariant(name: "All", layer: 50)
        let number = SubclassNames.numbers(of: "motorway", in: .roadMajor)[0]
        #expect(road([motorway, all]).variantIndex(subclass: number, in: .roadMajor) == 0)
        #expect(road([all, motorway]).variantIndex(subclass: number, in: .roadMajor) == 0 && all.selectsEverything)
    }

    @Test func aTagConditionNeedsTheTagAndAnAreaNeedsBothConditions() {
        let wide = StyleVariant(name: "Metre gauge", subclasses: ["rail"], tags: [TagCondition(key: "gauge", values: ["1000"])], layer: 40)
        let rail = SubclassNames.numbers(of: "rail", in: .railway)[0]
        let style = road([wide])
        #expect(style.variantIndex(subclass: rail, in: .railway, tag: { $0 == "gauge" ? "1000" : nil }) == 0)
        #expect(style.variantIndex(subclass: rail, in: .railway, tag: { $0 == "gauge" ? "1435" : nil }) == nil)
        #expect(style.variantIndex(subclass: rail, in: .railway) == nil, "a band that does not hold the tag never matches")
        let tram = SubclassNames.numbers(of: "tram", in: .railway)[0]
        #expect(style.variantIndex(subclass: tram, in: .railway, tag: { _ in "1000" }) == nil)
        #expect(TagCondition(key: "bridge").isMet(by: "yes") && !TagCondition(key: "bridge").isMet(by: nil))
    }

    @Test func aVariantReplacesOnlyWhatItSets() {
        let farmland = StyleVariant(name: "Farmland", subclasses: ["farmland"], fill: red)
        var cover = ClassStyle(fill: FillStyle(color: .color(0xDDE8C8)), visibleZoom: 10...24, layer: 11)
        cover.variants = [farmland]
        let number = SubclassNames.numbers(of: "farmland", in: .landcover)[0]
        let resolved = cover.resolved(subclass: number, in: .landcover)
        #expect(resolved.fill == red && resolved.layer == 11 && resolved.visibleZoom == 10...24)
    }

    @Test func variantsSurviveAJsonRoundTripAndAStyleWithoutThemIsUnchanged() throws {
        var style = MapStyle.standard
        var major = try #require(style.classes[.roadMajor])
        major.variants = [motorway, StyleVariant(name: "Gauge", tags: [TagCondition(key: "gauge", values: ["1000"]), TagCondition(key: "electrified")], visibleZoom: 8...24)]
        style.classes[.roadMajor] = major
        #expect(try MapStyle(json: try style.jsonData()) == style)
        #expect(!String(decoding: try MapStyle.watch.jsonData(), as: UTF8.self).contains("variants"), "a style with no variants is the file it was")
    }

    @Test func aWrongSubclassNameOrLayerOrKeyIsRefusedWithAHelpfulSentence() {
        func reason(_ body: String) -> String {
            let json = "{\"formatVersion\": 1, \"name\": \"T\", \"background\": \"#102030\", \"classes\": {\"roadMajor\": {\"layer\": 5, \"variants\": [\(body)]}}}"
            do { _ = try MapStyle(json: Data(json.utf8)); return "no error" } catch { return "\(error)" }
        }
        #expect(reason("{\"subclasses\": [\"motorwy\"]}").contains("unknown subclass 'motorwy'"))
        #expect(reason("{\"subclasses\": [\"motorwy\"]}").contains("motorway"))
        #expect(reason("{\"layer\": 120}").contains("between 0 and 99"))
        #expect(reason("{\"colour\": 1}").contains("colour"))
        #expect(reason("{\"tags\": [{\"key\": \"\"}]}").contains("OSM tag"))
        #expect(reason("{\"subclasses\": [\"trunk\"], \"layer\": 30}") == "no error")
    }

    @Test func anEditedLookGoesBackIntoTheVariantAndAnUnchangedPartFollowsTheClass() {
        let style = road([motorway])
        var effective = style.applying(motorway)
        effective.stroke?.width = LineWidth(points: ZoomValue(constant: 9))
        effective.layer = style.layer
        let updated = style.variant(motorway, updatedFrom: effective)
        #expect(updated.stroke?.width.points == ZoomValue(constant: 9))
        #expect(updated.layer == nil, "back to the class's own layer")
        #expect(updated.subclasses == ["motorway", "trunk"] && updated.name == "Motorways")
        // Nothing edited: a variant that set only a layer stays that way.
        #expect(style.variant(motorway, updatedFrom: style.applying(motorway)) == motorway)
    }

    @Test func aHiddenVariantHasNoStepAndSurvivesAJsonRoundTrip() throws {
        var style = MapStyle.watch
        var cls = ClassStyle(stroke: StrokeStyle(color: ZoomValue(constant: MapColor(hex: 0x999999)), width: LineWidth(points: ZoomValue(constant: 1))), layer: 20)
        cls.variants = [StyleVariant(name: "Underground", tags: [TagCondition(key: "location", values: ["underground"])], hidden: true)]
        style.classes[.powerLine] = cls
        #expect(style.drawSteps(atZoom: 15).filter { $0.featureClass == .powerLine }.map(\.variant) == [nil])
        #expect(try MapStyle(json: try style.jsonData()) == style)
        #expect(MapStyle.standard.classes[.powerLine]?.variants.first?.hidden == true)
        #expect(MapStyle.standard.classes[.powerLine]?.point != nil, "towers and poles are drawn")
    }
}

