import FeatureStore
import Foundation
import Testing

@testable import MapStyle

@Suite("Style JSON")
struct StyleJSONTests {
    private func parse(_ json: String) throws -> MapStyle { try MapStyle(json: Data(json.utf8)) }

    /// A small valid document with one road class; `extra` is spliced into that class.
    private func document(version: Int = 1, classBody: String = "\"layer\": 5") -> String {
        """
        {"formatVersion": \(version), "name": "Test", "background": "#102030",
         "classes": {"roadMajor": {\(classBody)}}}
        """
    }

    private func reason(_ json: String) -> String {
        do {
            _ = try parse(json)
            return "no error"
        } catch { return "\(error)" }
    }

    @Test(arguments: [MapStyle.standard, MapStyle.watch])
    func builtInStylesSurviveARoundTrip(style: MapStyle) throws {
        let data = try style.jsonData()
        #expect(try MapStyle(json: data) == style)
    }

    @Test func outputIsDeterministic() throws {
        #expect(try MapStyle.standard.jsonData() == MapStyle.standard.jsonData())
    }

    @Test func minimalDocumentUsesDefaults() throws {
        let style = try parse(document())
        #expect(style.name == "Test" && style.attribution == .full)
        #expect(style.background == MapColor(hex: 0x102030))
        let road = try #require(style.style(for: .roadMajor))
        #expect(road.layer == 5 && road.visibleZoom == 0...24 && road.fill == nil && road.stroke == nil)
        #expect(style.style(for: .path) == nil, "classes that are not listed are hidden")
    }

    @Test func zoomValuesAcceptAConstantOrStops() throws {
        let body = """
            "layer": 1, "visibleZoom": [10, 20],
            "stroke": {"color": [[12, "#000000"], [16, "#FFFFFF"]], "width": {"points": 2}}
            """
        let stroke = try #require(parse(document(classBody: body)).style(for: .roadMajor)?.stroke)
        #expect(stroke.width.points == ZoomValue(constant: 2))
        #expect(stroke.color.stops.count == 2 && stroke.color.value(atZoom: 20) == .white)
        #expect(stroke.cap == .round && stroke.join == .round && stroke.dash.isEmpty)
    }

    @Test func colourAlphaSurvivesARoundTrip() throws {
        var style = try parse(document(classBody: "\"layer\": 1, \"fill\": {\"color\": \"#11223380\"}"))
        let fill = try #require(style.style(for: .roadMajor)?.fill)
        #expect(abs(fill.color.value(atZoom: 0).alpha - 128.0 / 255) < 1e-9)
        style = try MapStyle(json: style.jsonData())
        #expect(style.style(for: .roadMajor)?.fill == fill)
    }

    @Test func attributionAndGroundWidthAreRead() throws {
        let json = """
            {"formatVersion": 1, "name": "T", "background": "#000000", "attribution": "compact",
             "classes": {"roadMajor": {"layer": 1, "stroke": {"color": "#FFFFFF",
               "width": {"points": [[12, 2], [16, 4]], "ground": {"metresPerLane": 3, "defaultLanes": 2}}}}}}
            """
        let style = try parse(json)
        #expect(style.attribution == .compact)
        let ground = try #require(style.style(for: .roadMajor)?.stroke?.width.ground)
        #expect(ground == GroundWidth(metresPerLane: 3, defaultLanes: 2, maximumLanes: 12))
    }

    @Test func labelSettingsAndLabelZoomAreReadAndRoundTrip() throws {
        let json = """
            {"formatVersion": 1, "name": "T", "background": "#000000", "labels": {"padding": 5, "maximumCount": 4},
             "classes": {"place": {"layer": 1, "label": {"size": 12, "color": "#FFFFFF", "visibleZoom": [13, 20]}}}}
            """
        let style = try parse(json)
        #expect(style.labels == LabelSettings(padding: 5, maximumCount: 4))
        #expect(style.style(for: .place)?.label?.visibleZoom == 13...20)
        #expect(try MapStyle(json: style.jsonData()) == style)
        #expect(try parse(document()).labels == LabelSettings())
        #expect(reason(json.replacingOccurrences(of: "\"maximumCount\": 4", with: "\"maximumCount\": -1")).contains("labels.maximumCount"))
        #expect(reason(json.replacingOccurrences(of: "\"padding\": 5", with: "\"padding\": -1")).contains("labels.padding"))
        #expect(reason(json.replacingOccurrences(of: "[13, 20]", with: "[20, 13]")).contains("label.visibleZoom"))
    }

    @Test func labelSettingsClampInvalidValues() {
        #expect(LabelSettings(padding: -3, maximumCount: -1) == LabelSettings(padding: 0, maximumCount: 0))
        #expect(LabelSettings(padding: .nan).padding == 0)
        #expect(MapStyle.watch.labels.maximumCount != nil && MapStyle.standard.labels.maximumCount == nil)
    }

    @Test func aBadFileFailsLoudlyWithTheLocation() {
        #expect(reason("not json").contains("not valid JSON"))
        #expect(reason(document(version: 2)).contains("version 2"))
        #expect(reason(document(classBody: "\"layer\": 1, \"visibleZom\": [1, 2]")).contains("unknown key 'visibleZom'"))
        #expect(reason(document(classBody: "\"visibleZoom\": [1, 2]")).contains("missing key 'layer'"))
        #expect(reason(document(classBody: "\"layer\": 1, \"visibleZoom\": [20, 10]")).contains("classes.roadMajor.visibleZoom"))
        #expect(reason(document(classBody: "\"layer\": 1, \"fill\": {\"color\": \"red\"}")).contains("classes.roadMajor.fill.color"))
        #expect(reason(document(classBody: "\"layer\": 1, \"fill\": {\"color\": \"#12345\"}")).contains("not a colour"))
        #expect(reason(document(classBody: "\"layer\": 1, \"fill\": {\"color\": []}")).contains("at least one"))
        #expect(
            reason(document(classBody: "\"layer\": 1, \"stroke\": {\"color\": \"#000000\", \"width\": {\"points\": -1}}"))
                .contains("classes.roadMajor.stroke.width.points"))
        #expect(
            reason(document(classBody: "\"layer\": 1, \"stroke\": {\"color\": \"#000000\", \"width\": {\"points\": 1}, \"cap\": \"flat\"}"))
                .contains("classes.roadMajor.stroke.cap"))
        #expect(reason(document().replacingOccurrences(of: "roadMajor", with: "motorway")).contains("unknown feature class 'motorway'"))
    }

    @Test func aStyleFileWithoutCountryBorderDrawsBordersWithTheBoundaryStyle() throws {
        var object = try #require(JSONSerialization.jsonObject(with: MapStyle.standard.jsonData()) as? [String: Any])
        var classes = try #require(object["classes"] as? [String: Any])
        #expect(classes.removeValue(forKey: "countryBorder") != nil)
        object["classes"] = classes
        let old = try MapStyle(json: JSONSerialization.data(withJSONObject: object))
        #expect(old.style(for: .countryBorder) == old.style(for: .boundary))
        // A file that has the class keeps its own style.
        #expect(try MapStyle(json: MapStyle.standard.jsonData()).style(for: .countryBorder)?.stroke?.casing != nil)
        // And a style without boundaries (the Watch) still has no border.
        #expect(MapStyle.watch.style(for: .countryBorder) == nil)
    }

    @Test func aStyleFileWithoutPavementHidesSidewalks() throws {
        var object = try #require(JSONSerialization.jsonObject(with: MapStyle.standard.jsonData()) as? [String: Any])
        var classes = try #require(object["classes"] as? [String: Any])
        #expect(classes.removeValue(forKey: "pavement") != nil)
        object["classes"] = classes
        #expect(try MapStyle(json: JSONSerialization.data(withJSONObject: object)).style(for: .pavement) == nil)
        // Addresses are never drawn.
        #expect(MapStyle.standard.style(for: .address) == nil && MapStyle.watch.style(for: .address) == nil)
    }

    @Test func aStyleFileWithoutRoadServiceDrawsServiceRoadsAsStreets() throws {
        var object = try #require(JSONSerialization.jsonObject(with: MapStyle.standard.jsonData()) as? [String: Any])
        var classes = try #require(object["classes"] as? [String: Any])
        #expect(classes.removeValue(forKey: "roadService") != nil)
        object["classes"] = classes
        let old = try MapStyle(json: JSONSerialization.data(withJSONObject: object))
        #expect(old.style(for: .roadService) == old.style(for: .roadMinor))
        #expect(try MapStyle(json: MapStyle.standard.jsonData()).style(for: .roadService) != old.style(for: .roadMinor))
    }

    @Test func layersAreLimitedToZeroThroughNinetyNine() throws {
        #expect(try parse(document(classBody: "\"layer\": 99, \"casingLayer\": 0")).style(for: .roadMajor)?.layer == 99)
        #expect(reason(document(classBody: "\"layer\": 100")).contains("layer"))
        #expect(reason(document(classBody: "\"layer\": -1")).contains("between 0 and 99"))
        #expect(reason(document(classBody: "\"layer\": 5, \"casingLayer\": 120")).contains("casingLayer"))
        // The built-in styles obey the rule.
        for style in [MapStyle.standard, MapStyle.watch] {
            for (featureClass, classStyle) in style.classes {
                #expect((0...99).contains(classStyle.layer) && (0...99).contains(classStyle.casingLayer ?? 0), "\(featureClass)")
            }
        }
    }

    @Test func bridgeAndTunnelStylesAreReadStrictly() throws {
        let style = try parse(document(classBody: """
            "layer": 5, "stroke": {"color": "#000000", "width": {"points": 1}},
            "bridge": {"casing": {"color": "#404040", "extraPoints": [[12, 0.5], [16, 1.5]]}},
            "tunnel": {"opacity": 0.4, "dash": [4, 2]}
            """))
        let road = try #require(style.style(for: .roadMajor))
        #expect(road.bridge?.casing.extraPoints.value(atZoom: 16) == 1.5)
        #expect(road.tunnel == TunnelStyle(opacity: 0.4, dash: [4, 2]))
        #expect(try MapStyle(json: style.jsonData()) == style)
        // The tunnel opacity defaults, and is checked.
        #expect(try parse(document(classBody: "\"layer\": 5, \"tunnel\": {}")).style(for: .roadMajor)?.tunnel == TunnelStyle(opacity: 0.5))
        #expect(reason(document(classBody: "\"layer\": 5, \"tunnel\": {\"opacity\": 2}")).contains("opacity"))
        #expect(reason(document(classBody: "\"layer\": 5, \"tunnel\": {\"dash\": [-1]}")).contains("dash"))
        #expect(reason(document(classBody: "\"layer\": 5, \"bridge\": {}")).contains("casing"))
        #expect(reason(document(classBody: "\"layer\": 5, \"bridge\": {\"casing\": {\"color\": \"#000000\", \"extraPoints\": 1}, \"width\": 2}")).contains("width"))
    }

    @Test func classNamesInTheFileFormatArePinned() throws {
        // These names are the file format. Renaming a FeatureClass case must not silently break users' style files.
        let names = [
            "other", "path", "track", "roadMajor", "roadMinor", "railway", "waterLine", "waterArea", "forest", "landcover",
            "landuseUrban", "building", "peak", "place", "poiAnchor", "poi", "boundary", "powerLine", "piste", "aerialway",
            "tree", "barrier", "transportStop", "roadPoint", "countryBorder", "address", "pavement", "cliff", "sea", "coastline", "roadArea", "roadService",
            "waterEdge", "parkBorder", "parkBorderSea", "pier", "militaryArea", "glacier", "bareGround", "wetland", "sand", "landUse", "riverName",
        ]
        #expect(FeatureClass.allCases.map { String(describing: $0) } == names)
        for name in names {
            let json = document().replacingOccurrences(of: "roadMajor", with: name)
            // `boundary`, `roadMinor`, `parkBorder` and `landuseUrban` also fill in the classes that were added after them, for old style files.
            let expected = ["boundary": 4, "roadMinor": 2, "parkBorder": 2, "landuseUrban": 2, "landcover": 5][name] ?? 1
            #expect(try parse(json).classes.count == expected, "class \(name)")
        }
    }

    @Test func aStyleFileWithoutGlaciersBareGroundAndWetlandDrawsThemLikeLandCover() throws {
        let style = try parse(document().replacingOccurrences(of: "roadMajor", with: "landcover"))
        for split in [FeatureClass.glacier, .bareGround, .wetland, .sand] { #expect(style.classes[split] == style.classes[.landcover], "\(split)") }
    }

    @Test func aStyleFileWithoutMilitaryLandDrawsItLikeUrbanLand() throws {
        let style = try parse(document().replacingOccurrences(of: "roadMajor", with: "landuseUrban"))
        #expect(style.classes[.militaryArea] != nil && style.classes[.militaryArea] == style.classes[.landuseUrban])
    }

    @Test func malformedZoomValuesAreRejected() {
        func fill(_ color: String) -> String { document(classBody: "\"layer\": 1, \"fill\": {\"color\": \(color)}") }
        #expect(reason(fill("[[12, \"#000000\", 3]]")).contains("exactly two items"))
        #expect(reason(fill("[[12]]")).contains("classes.roadMajor.fill.color"))
        #expect(reason(fill("[\"#000000\"]")).contains("classes.roadMajor.fill.color"))
        #expect(reason(fill("null")).contains("classes.roadMajor.fill.color"))
        #expect(reason("[1, 2]").contains("Invalid style"))
        #expect(reason("").contains("not valid JSON"))
        #expect(reason("{\"formatVersion\": 1, \"name\":").contains("not valid JSON"))
    }

    @Test func stopsAreSortedAndALaterDuplicateWins() throws {
        let body = "\"layer\": 1, \"point\": {\"radius\": [[16, 8], [12, 2], [12, 3]], \"color\": \"#000000\"}"
        let radius = try #require(parse(document(classBody: body)).style(for: .roadMajor)?.point?.radius)
        #expect(radius.stops.map(\.zoom) == [12, 16] && radius.value(atZoom: 12) == 3)
    }

    @Test func aSingleStopAwayFromZoomZeroSurvivesARoundTrip() throws {
        let body = "\"layer\": 1, \"point\": {\"radius\": [[12, 4]], \"color\": \"#000000\"}"
        let style = try parse(document(classBody: body))
        #expect(try MapStyle(json: style.jsonData()) == style)
        #expect(ZoomValue<Double>(stops: []) == nil)
    }

    @Test func anOversizedDocumentIsRejected() {
        let big = Data(repeating: 0x20, count: MapStyle.maximumJSONSize + 1)
        #expect(throws: MapStyleError.self) { try MapStyle(json: big) }
    }

    @Test func unsupportedVersionIsATypedError() {
        #expect(throws: MapStyleError.unsupportedVersion(7)) { try parse(document(version: 7)) }
    }
}

@Suite("Label thinning")
struct LabelThinningStyleTests {
    @Test func theStandardStyleThinsThePlaceNamesAtLowZoomOnly() {
        let radius = MapStyle.standard.classes[.place]?.label?.thinningRadius
        #expect(radius?.value(atZoom: 10) == 80 && radius?.value(atZoom: 12) == 0)
        // The radius grows as the map zooms out, so a map of a whole region names only its largest places.
        #expect(radius?.value(atZoom: 8) == 120 && radius?.value(atZoom: 3) == 300 && radius?.value(atZoom: 1) == 300)
    }

    @Test func theRadiusSurvivesAJsonRoundTripAndABadOneIsRefused() throws {
        let again = try MapStyle(json: try MapStyle.standard.jsonData())
        #expect(again.classes[.place]?.label?.thinningRadius.value(atZoom: 10) == 80)
        #expect(again.classes[.place]?.label?.cityThinningFactor == 0.4)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(LabelStyle.self, from: Data("{\"size\": 10, \"color\": \"#000000\", \"cityThinningFactor\": 2}".utf8)) }
        func decode(_ json: String) throws -> LabelStyle { try JSONDecoder().decode(LabelStyle.self, from: Data(json.utf8)) }
        let base = ##""size": 10, "color": "#000000""##
        #expect(throws: (any Error).self) { try decode("{\(base), \"thinningRadius\": \"far\"}") }
        #expect(throws: (any Error).self) { try decode("{\(base), \"thinningRadius\": -5}") }
        #expect(try decode("{\(base), \"thinningRadius\": [[10, 80], [11, 0]]}").thinningRadius.value(atZoom: 10) == 80)
    }
}

@Suite("Population scale")
struct PopulationScaleTests {
    private let scale = PopulationScale(smallest: 0.5, decades: 2, strength: ZoomValue((10, 1), (13, 0)))!

    @Test func theLargestPlaceKeepsTheFullSizeAndASmallerOneIsSmallerByTheLogarithm() {
        #expect(scale.scale(population: 360_000, largest: 360_000, atZoom: 9) == 1)
        #expect(abs(scale.scale(population: 36_000, largest: 360_000, atZoom: 9) - 0.75) < 1e-9, "a tenth: half way down")
        #expect(abs(scale.scale(population: 3_600, largest: 360_000, atZoom: 9) - 0.5) < 1e-9, "a hundredth: the smallest")
        #expect(scale.scale(population: 100, largest: 360_000, atZoom: 9) == 0.5, "never below the smallest")
        let houten = scale.scale(population: 50_000, largest: 360_000, atZoom: 9)
        #expect(houten > 0.75 && houten < 0.85)
    }

    @Test func itIsRelativeToTheLargestPlaceInView() {
        // A town of 8,000 is the largest in a Norwegian valley: full size. Next to Utrecht it is small.
        #expect(scale.scale(population: 8_000, largest: 8_000, atZoom: 9) == 1)
        #expect(scale.scale(population: 8_000, largest: 360_000, atZoom: 9) < 0.6)
        #expect(scale.scale(population: 500_000, largest: 360_000, atZoom: 9) == 1, "a larger one than the given largest is not enlarged")
    }

    @Test func theEffectFadesOutWithZoom() {
        #expect(scale.scale(population: 3_600, largest: 360_000, atZoom: 13) == 1 && scale.scale(population: 3_600, largest: 360_000, atZoom: 16) == 1)
        #expect(abs(scale.scale(population: 3_600, largest: 360_000, atZoom: 11.5) - 0.75) < 1e-9)
    }

    @Test func theStandardStyleWritesHoutenSmallerThanUtrechtAtZoom9() {
        let scale = MapStyle.standard.classes[.place]?.label?.populationScale
        #expect(scale?.scale(population: 360_000, largest: 360_000, atZoom: 9) == 1)
        #expect((scale?.scale(population: 50_000, largest: 360_000, atZoom: 9) ?? 1) < 0.85)
        #expect(scale?.scale(population: 50_000, largest: 360_000, atZoom: 14) == 1)
    }

    @Test func itSurvivesAJsonRoundTripAndBadNumbersAreRefused() throws {
        let again = try MapStyle(json: try MapStyle.standard.jsonData())
        #expect(again.classes[.place]?.label?.populationScale == MapStyle.standard.classes[.place]?.label?.populationScale)
        func decode(_ json: String) throws -> PopulationScale { try JSONDecoder().decode(PopulationScale.self, from: Data(json.utf8)) }
        #expect(try decode(#"{"smallest": 0.5, "decades": 2}"#).decades == 2)
        #expect(throws: (any Error).self) { try decode(#"{"smallest": 0, "decades": 2}"#) }
        #expect(throws: (any Error).self) { try decode(#"{"smallest": 1.5, "decades": 2}"#) }
        #expect(throws: (any Error).self) { try decode(#"{"smallest": 0.5, "decades": 0}"#) }
        #expect(throws: (any Error).self) { try decode(#"{"smallest": 0.5}"#) }
        #expect(throws: (any Error).self) { try decode(#"{"smallest": 0.5, "decades": 2, "strenth": 1}"#) }
        #expect(PopulationScale(smallest: 0, decades: 1) == nil)
    }
}
