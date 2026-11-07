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

    @Test func unsupportedVersionIsATypedError() {
        #expect(throws: MapStyleError.unsupportedVersion(7)) { try parse(document(version: 7)) }
    }
}
