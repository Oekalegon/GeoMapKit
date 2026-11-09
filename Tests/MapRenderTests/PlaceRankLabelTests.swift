import FeatureStore
import GeoCore
import MapStyle
import Testing

@testable import MapRender

/// At low zoom only the cities and the larger towns are named; the smaller towns follow from zoom 10.
@Suite("Place rank labels")
struct PlaceRankLabelTests {
    private func scene(zoom: Double) -> MapScene {
        let viewport = MapViewport(center: Coordinate(latitude: 52, longitude: 5), zoom: zoom, width: 800, height: 600)
        let ranks: [(UInt8, String, Double)] = [
            (PlaceRank.city, "Utrecht", 300), (PlaceRank.town, "Gouda", 400), (PlaceRank.smallTown, "Vianen", 500),
            (PlaceRank.village, "Bilthoven", 600),
        ]
        let points = ranks.enumerated().map { index, rank in
            ScenePoint(
                featureClass: .place, objectID: Int64(index), position: ScreenPoint(x: rank.2, y: 300), name: rank.1, subclass: rank.0)
        }
        return MapScene(
            viewport: viewport, band: .overview, steps: [SceneStep(step: DrawStep(featureClass: .place, part: .body), points: points)],
            cellCount: 1)
    }

    private func names(atZoom zoom: Double, style: MapStyle = .standard) -> Set<String> {
        Set(LabelCandidates.collect(from: scene(zoom: zoom), style: style).map(\.text))
    }

    @Test func atZoom9OnlyTheCityAndTheLargerTownsAreNamedAndTheVillageIsLeftToItsBand() {
        // The village is not held back by the style (its band, the mid band, is what keeps it out of zoom 9).
        #expect(names(atZoom: 9) == ["Utrecht", "Gouda", "Bilthoven"])
    }

    @Test func aSmallTownIsNamedFromZoom10() {
        #expect(names(atZoom: 9.9).contains("Vianen") == false)
        #expect(names(atZoom: 10).contains("Vianen"))
    }

    @Test func aStyleWithoutTheTableNamesEveryRank() {
        var style = MapStyle.standard
        style.classes[.place]?.label?.subclassMinimumZoom = [:]
        #expect(names(atZoom: 9, style: style).contains("Vianen"))
    }
}
