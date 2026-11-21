import MapRender
import MapStyle
import Testing

@testable import TrackOverlays

@Suite("Heat map legend")
struct HeatMapLegendTests {
    @Test("The standard scale gives the steps 1, 2–3, 4–9, 10–29 and 30+, with the look of the scale")
    func standard() {
        let legend = HeatMapLegend()
        #expect(legend.entries.map(\.label) == ["1", "2–3", "4–9", "10–29", "30+"])
        #expect(legend.entries.map(\.style) == HeatMapScale.standard.steps.map(\.style))
        #expect(legend.entries.last?.maximumCount == nil)
    }

    @Test("Another scale gives its own steps, and a single step is open at the top")
    func other() throws {
        let style = OverlayLineStyle(color: MapColor(red: 0, green: 0, blue: 1, alpha: 1), width: 2)
        let scale = try #require(HeatMapScale(steps: [HeatMapScale.Step(minimumCount: 3, style: style), HeatMapScale.Step(minimumCount: 4, style: style)]))
        #expect(HeatMapLegend(scale: scale).entries.map(\.label) == ["3", "4+"])
        let single = try #require(HeatMapScale(steps: [HeatMapScale.Step(minimumCount: 1, style: style)]))
        #expect(HeatMapLegend(scale: single).entries.map(\.label) == ["1+"])
    }
}
