import Testing

@testable import MapStyle

@Suite("AttributionDisplay")
struct AttributionDisplayTests {
    private let credit = "© OpenStreetMap contributors, ODbL"

    @Test func fullKeepsTheCreditCompactShortensItHiddenDropsIt() {
        #expect(AttributionDisplay.full.text(for: credit) == credit)
        #expect(AttributionDisplay.compact.text(for: credit) == "© OSM")
        #expect(AttributionDisplay.hidden.text(for: credit) == nil)
    }

    @Test func anEmptyCreditNeverDrawsAMark() {
        for display in AttributionDisplay.allCases { #expect(display.text(for: "") == nil) }
    }

    @Test func standardShowsTheFullCreditAndWatchTheShortMark() {
        #expect(MapStyle.standard.attribution == .full)
        #expect(MapStyle.watch.attribution == .compact)
    }
}
