import FeatureStore
import GeoCore
import MapStyle
import Testing

@testable import MapRender

/// At low zoom a place is named only when no larger place is near: the density follows the country.
@Suite("Place name thinning")
struct PlaceRankLabelTests {
    private func place(_ id: Int64, _ name: String, x: Double, subclass: UInt8 = 2, population: Int? = nil) -> ScenePoint {
        ScenePoint(featureClass: .place, objectID: id, position: ScreenPoint(x: x, y: 300), name: name, subclass: subclass, population: population)
    }

    private func names(_ points: [ScenePoint], zoom: Double, style: MapStyle = .standard) -> Set<String> {
        let viewport = MapViewport(center: Coordinate(latitude: 52, longitude: 5), zoom: zoom, width: 800, height: 600)
        let scene = MapScene(
            viewport: viewport, band: .overview, steps: [SceneStep(step: DrawStep(featureClass: .place, part: .body), points: points)],
            cellCount: 1)
        return Set(LabelCandidates.collect(from: scene, style: style).map(\.text))
    }

    @Test func aSmallPlaceNextToABigOneIsNotNamedAndOneFarAwayIs() {
        let points = [
            place(1, "Gouda", x: 300, population: 74_000), place(2, "Waddinxveen", x: 340, population: 31_000),
            place(3, "Leerdam", x: 650, population: 21_000),
        ]
        #expect(names(points, zoom: 9) == ["Gouda", "Leerdam"])
    }

    @Test func theLargerOfTwoNeighboursWinsWhateverTheOrder() {
        let points = [place(1, "Small", x: 300, population: 5_000), place(2, "Big", x: 330, population: 50_000)]
        #expect(names(points, zoom: 9) == ["Big"])
        #expect(names(points.reversed(), zoom: 9) == ["Big"])
    }

    @Test func aCityBeatsATownAndATownWithoutPopulationLosesToOneWith() {
        #expect(names([place(1, "Town", x: 300, population: 90_000), place(2, "City", x: 320, subclass: 1, population: 1_000)], zoom: 9) == ["City"])
        #expect(names([place(1, "Untagged", x: 300), place(2, "Tagged", x: 320, population: 8_000)], zoom: 9) == ["Tagged"])
    }

    @Test func theSameTwoPlacesAreBothNamedOnceZoomedInAndWhenTheyAreFarApart() {
        let points = [place(1, "Gouda", x: 300, population: 74_000), place(2, "Waddinxveen", x: 340, population: 31_000)]
        #expect(names(points, zoom: 12) == ["Gouda", "Waddinxveen"], "the thinning has faded out by zoom 11")
        let far = [place(1, "Gouda", x: 100, population: 74_000), place(2, "Waddinxveen", x: 300, population: 31_000)]
        #expect(names(far, zoom: 9) == ["Gouda", "Waddinxveen"])
    }

    @Test func aStyleWithoutThinningNamesEveryPlace() {
        var style = MapStyle.standard
        style.classes[.place]?.label?.thinningRadius = ZoomValue(constant: 0)
        let points = [place(1, "Gouda", x: 300, population: 74_000), place(2, "Waddinxveen", x: 340, population: 31_000)]
        #expect(names(points, zoom: 9, style: style) == ["Gouda", "Waddinxveen"])
    }

    private func sizes(_ points: [ScenePoint], zoom: Double) -> [String: Double] {
        let viewport = MapViewport(center: Coordinate(latitude: 52, longitude: 5), zoom: zoom, width: 800, height: 600)
        let scene = MapScene(
            viewport: viewport, band: .overview, steps: [SceneStep(step: DrawStep(featureClass: .place, part: .body), points: points)],
            cellCount: 1)
        return Dictionary(uniqueKeysWithValues: LabelCandidates.collect(from: scene, style: .standard).map { ($0.text, $0.fontSize) })
    }

    @Test func aSmallerPlaceIsWrittenSmallerAtLowZoomAndEqualWhenZoomedIn() throws {
        let points = [
            place(1, "Utrecht", x: 100, subclass: 1, population: 360_000), place(2, "Houten", x: 400, population: 50_000),
            place(3, "Untagged", x: 700, subclass: 3),
        ]
        let low = sizes(points, zoom: 9)
        let utrecht = try #require(low["Utrecht"]), houten = try #require(low["Houten"]), untagged = try #require(low["Untagged"])
        #expect(houten < 0.85 * utrecht && untagged < houten, "a village without population is taken as 2,000 people")
        let near = sizes(points, zoom: 14)
        #expect(near["Utrecht"] == near["Houten"] && near["Houten"] == near["Untagged"])
        #expect(utrecht == MapStyle.standard.classes[.place]?.label?.size.value(atZoom: 9), "a city has the size of the style")
    }

    @Test func theSizesAreRelativeToTheLargestPlaceInView() throws {
        let valley = [place(1, "Town", x: 100, population: 8_000), place(2, "Village", x: 400, subclass: 3, population: 800)]
        let withCity = valley + [place(3, "City", x: 700, subclass: 1, population: 360_000)]
        let alone = sizes(valley, zoom: 9), crowded = sizes(withCity, zoom: 9)
        #expect(alone["Town"] == MapStyle.standard.classes[.place]?.label?.size.value(atZoom: 9), "the largest in view has the size of the style")
        let townCrowded = try #require(crowded["Town"]), townAlone = try #require(alone["Town"]), village = try #require(alone["Village"])
        #expect(townCrowded < townAlone)
        #expect(village < townAlone)
    }

    @Test func aPlaceOutOfViewDoesNotSetTheScale() throws {
        let points = [place(1, "Town", x: 100, population: 8_000), place(3, "FarCity", x: 5_000, subclass: 1, population: 360_000)]
        #expect(sizes(points, zoom: 9)["Town"] == MapStyle.standard.classes[.place]?.label?.size.value(atZoom: 9))
    }
}
