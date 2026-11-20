import Testing

@testable import GeoMapKitDemo

/// The state of the heat map on the map. Making the frames is the package's (`TrackHeatMap`) and is tested there.
@MainActor
@Suite("Heat map model")
struct HeatMapModelTests {
    @Test("A new model draws nothing and plays nothing")
    func idle() {
        let model = HeatMapModel()
        #expect(model.overlays.isEmpty && model.frame == nil && model.lapse == nil && !model.isPlaying && !model.isBusy && model.month == nil)
        model.play()
        model.stop()
        model.hide()
        #expect(!model.isPlaying && model.overlays.isEmpty)
    }

    @Test("The choices of a frame map to the spans of the time-lapse")
    func spans() {
        #expect(HeatMapModel.SpanChoice.cumulative.span == .cumulative)
        #expect(HeatMapModel.SpanChoice.month.span == .last(months: 1))
        #expect(HeatMapModel.SpanChoice.year.span == .last(months: 12))
    }
}
