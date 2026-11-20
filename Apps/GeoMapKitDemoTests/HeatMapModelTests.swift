import GeoCore
import MapRender
import Testing

@testable import GeoMapKitDemo

/// The state of the heat map on the map. Making the frames is the package's (`TrackHeatMap`) and is tested there.
@MainActor
@Suite("Heat map model")
struct HeatMapModelTests {
    @Test("A new model draws nothing and plays nothing")
    func idle() async {
        let model = HeatMapModel()
        #expect(model.overlays.isEmpty && model.frame == nil && model.lapse == nil && !model.isPlaying && !model.isBusy && model.month == nil)
        await model.play()
        await model.stop()
        await model.show(3)
        model.hide()
        #expect(!model.isPlaying && model.overlays.isEmpty && model.viewBox == nil)
    }

    @Test("The view of the map gives the area, and a change of the database marks only a picture that is on the map")
    func viewAndStale() {
        let model = HeatMapModel()
        model.databaseChanged()
        #expect(!model.isOutOfDate)
        model.viewport = MapViewport(center: Coordinate(latitude: 60, longitude: 10), zoom: 12, width: 800, height: 600)
        let box = model.viewBox
        #expect(box?.contains(Coordinate(latitude: 60, longitude: 10)) == true)
    }

    @Test("The choices of a frame map to the spans of the time-lapse")
    func spans() {
        #expect(HeatMapModel.SpanChoice.cumulative.span == .cumulative)
        #expect(HeatMapModel.SpanChoice.month.span == .last(months: 1))
        #expect(HeatMapModel.SpanChoice.year.span == .last(months: 12))
    }
}
