import GeoCore
import MapRender
import Testing

@testable import MapUI

@Suite("MapFramePlan")
struct MapFramePlanTests {
    private let centre = Coordinate(latitude: 47.14, longitude: 9.52)
    private let width = 400.0
    private let height = 300.0

    private func requested(_ centre: Coordinate? = nil, zoom: Double = 15) -> MapViewport {
        MapViewport(center: centre ?? self.centre, zoom: zoom, width: width, height: height)
    }

    /// The frame viewport the model would draw for `requested`: the view plus the margin.
    private func frameViewport(zoom: Double = 15) -> MapViewport {
        let margin = MapFramePlan.margin(forViewWidth: width, viewHeight: height)
        return MapViewport(center: centre, zoom: zoom, width: width + 2 * margin, height: height + 2 * margin)
    }

    @Test func marginIsHalfTheLargerSide() {
        #expect(MapFramePlan.margin(forViewWidth: 400, viewHeight: 300) == 200)
        #expect(MapFramePlan.margin(forViewWidth: 301, viewHeight: 10) == 151)
    }

    @Test func aFreshFrameFillsTheViewExactlyAndNeedsNoNewOne() {
        let plan = MapFramePlan(frame: frameViewport(), requested: requested())
        #expect(plan.coversView && !plan.zoomDiffers)
        #expect(abs(plan.centre.x - width / 2) < 1e-6 && abs(plan.centre.y - height / 2) < 1e-6)
        #expect(plan.width == 800 && plan.height == 700)
        #expect(!plan.needsNewFrame(interacting: false) && !plan.needsNewFrame(interacting: true))
    }

    @Test func aSmallPanMovesTheFrameWithoutDrawingAgain() {
        // Move the view centre 50 points east: the frame must shift 50 points to the west.
        let start = requested()
        let moved = requested(start.coordinate(at: ScreenPoint(x: width / 2 + 50, y: height / 2)))
        let plan = MapFramePlan(frame: frameViewport(), requested: moved)
        #expect(abs(plan.centre.x - (width / 2 - 50)) < 1e-6)
        #expect(plan.coversView)
        #expect(!plan.needsNewFrame(interacting: false), "50 points is within a quarter of the screen")
    }

    @Test func panningFarEnoughNeedsANewFrameEvenWhileInteracting() {
        let start = requested()
        let far = requested(start.coordinate(at: ScreenPoint(x: width / 2 + 350, y: height / 2)))
        let plan = MapFramePlan(frame: frameViewport(), requested: far)
        #expect(!plan.coversView)
        #expect(plan.needsNewFrame(interacting: true))
    }

    @Test func driftBeyondAQuarterScreenIsFixedWhenTheGestureEnds() {
        let start = requested()
        let moved = requested(start.coordinate(at: ScreenPoint(x: width / 2 + 150, y: height / 2)))
        let plan = MapFramePlan(frame: frameViewport(), requested: moved)
        #expect(plan.coversView && plan.drift > plan.driftLimit)
        #expect(!plan.needsNewFrame(interacting: true))
        #expect(plan.needsNewFrame(interacting: false))
    }

    @Test func zoomingScalesTheFrameAndRedrawsWhenTheGestureEnds() {
        let plan = MapFramePlan(frame: frameViewport(zoom: 15), requested: requested(zoom: 15.5))
        #expect(plan.zoomDiffers)
        #expect(abs(plan.width - 800 * 2.0.squareRoot()) < 1e-6)
        #expect(plan.coversView, "zooming in keeps the centre covered")
        #expect(!plan.needsNewFrame(interacting: true))
        #expect(plan.needsNewFrame(interacting: false))
    }

    @Test func zoomingOutFarUncoversTheViewAndForcesANewFrame() {
        let plan = MapFramePlan(frame: frameViewport(zoom: 15), requested: requested(zoom: 13))
        #expect(!plan.coversView && plan.needsNewFrame(interacting: true))
    }
}
