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

    @Test func classNamesInTheFileFormatArePinned() throws {
        // These names are the file format. Renaming a FeatureClass case must not silently break users' style files.
        let names = [
            "other", "path", "track", "roadMajor", "roadMinor", "railway", "waterLine", "waterArea", "forest", "landcover",
            "landuseUrban", "building", "peak", "place", "poiAnchor", "poi", "boundary", "powerLine", "piste", "aerialway",
            "tree", "barrier", "transportStop", "roadPoint",
        ]
        #expect(FeatureClass.allCases.map { String(describing: $0) } == names)
        for name in names {
            let json = document().replacingOccurrences(of: "roadMajor", with: name)
            #expect(try parse(json).classes.count == 1)
        }
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
