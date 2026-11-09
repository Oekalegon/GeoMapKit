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
}
