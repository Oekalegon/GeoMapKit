import FeatureStore
import Testing

@testable import MapRender

@Suite("Band selection")
struct BandSelectionTests {
    @Test func zoomPicksTheBand() {
        #expect(ZoomBand.band(forZoom: 8) == .overview)
        #expect(ZoomBand.band(forZoom: 11.99) == .overview)
        #expect(ZoomBand.band(forZoom: 12) == .mid)
        #expect(ZoomBand.band(forZoom: 14.99) == .mid)
        #expect(ZoomBand.band(forZoom: 15) == .detail)
        #expect(ZoomBand.band(forZoom: 22) == .detail)
    }

    @Test func missingBandFallsBackToTheNearestFinerOne() {
        // The Watch file holds mid and detail only.
        #expect(ZoomBand.band(forZoom: 10, available: [.mid, .detail]) == .mid)
        #expect(ZoomBand.band(forZoom: 13, available: [.mid, .detail]) == .mid)
    }

    @Test func fallsBackToACoarserBandWhenNothingFinerExists() {
        #expect(ZoomBand.band(forZoom: 16, available: [.overview, .mid]) == .mid)
    }

    @Test func noBandsGivesNil() {
        #expect(ZoomBand.band(forZoom: 16, available: []) == nil)
    }
}
