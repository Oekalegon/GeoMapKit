import Foundation
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

    @Test func theMarginIsCappedSoTheImageStaysSmall() {
        #expect(MapFramePlan.margin(forViewWidth: 1032, viewHeight: 1376) == 256)
        #expect(MapFramePlan.margin(forViewWidth: 184, viewHeight: 224) == 112)
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
        #expect(!plan.needsNewFrame(interacting: false), "50 points is within half the margin")
    }

    @Test func panningFarEnoughNeedsANewFrameEvenWhileInteracting() {
        let start = requested()
        let far = requested(start.coordinate(at: ScreenPoint(x: width / 2 + 350, y: height / 2)))
        let plan = MapFramePlan(frame: frameViewport(), requested: far)
        #expect(!plan.coversView)
        #expect(plan.needsNewFrame(interacting: true))
    }

    @Test func driftBeyondHalfTheMarginStartsANewFrameDuringTheGestureToo() {
        let start = requested()
        let moved = requested(start.coordinate(at: ScreenPoint(x: width / 2 + 150, y: height / 2)))
        let plan = MapFramePlan(frame: frameViewport(), requested: moved)
        #expect(plan.coversView && plan.drift > plan.driftLimit)
        #expect(plan.needsNewFrame(interacting: true), "the next frame takes time, so it starts before the edge shows")
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

    // MARK: Bearing

    private func turned(_ bearing: Double, size: (Double, Double) = (width: 400, height: 300)) -> (frame: MapViewport, plan: (Double) -> MapFramePlan) {
        let margin = MapFramePlan.margin(forViewWidth: size.0, viewHeight: size.1)
        let frame = MapViewport(center: centre, zoom: 15, width: size.0 + 2 * margin, height: size.1 + 2 * margin, bearing: bearing)
        return (frame, { newBearing in
            MapFramePlan(frame: frame, requested: MapViewport(center: centre, zoom: 15, width: size.0, height: size.1, bearing: newBearing))
        })
    }

    @Test func theMarginIsEnoughForTheCircleAroundTheView() {
        // 400 x 800: the half diagonal is 447, so a frame 894 wide and high needs a margin of 247; the margin is 256 (the cap).
        let needed = (hypot(400.0, 800.0) / 2 - 200).rounded(.up)
        #expect(MapFramePlan.margin(forViewWidth: 400, viewHeight: 800) >= needed)
        for (width, height) in [(200.0, 240.0), (400, 600), (600, 600), (500, 90)] {
            let circle = hypot(width, height) / 2 - min(width, height) / 2
            #expect(MapFramePlan.margin(forViewWidth: width, viewHeight: height) >= circle.rounded(.up))
        }
    }

    @Test func aFrameIsTurnedByTheDifferenceOfTheBearings() {
        let (_, plan) = turned(0)
        #expect(plan(0).rotation == 0)
        #expect(plan(30).rotation == -30, "the map turned anticlockwise on screen when the bearing goes up")
        #expect(abs(turned(350).plan(10).rotation - -20) < 1e-9, "the short way round")
    }

    @Test func aPhoneSizedFrameCoversTheViewAtEveryBearing() {
        let (_, plan) = turned(0, size: (400, 800))
        for bearing in stride(from: 0.0, to: 360, by: 5) {
            #expect(plan(bearing).coversView, "bearing \(bearing)")
        }
    }

    @Test func aTurnedFrameOfALargeViewStopsCoveringAndForcesANewFrameDuringTheGesture() {
        let (_, plan) = turned(0, size: (1400, 1000))
        #expect(plan(5).coversView && !plan(5).needsNewFrame(interacting: true))
        #expect(plan(45).needsNewFrame(interacting: true), "the corners of the view are past the frame")
    }

    @Test func turningRedrawsWhenTheGestureEndsButNotForAHalfDegree() {
        let (_, plan) = turned(0)
        #expect(!plan(20).needsNewFrame(interacting: true), "the image is only turned meanwhile")
        #expect(plan(20).needsNewFrame(interacting: false))
        #expect(!plan(0.5).needsNewFrame(interacting: false), "below the tolerance")
        #expect(plan(1.5).needsNewFrame(interacting: false))
    }
}

@Suite("MapView centre")
struct MapViewCentreTests {
    @Test func panningPastThePoleOrTheAntimeridianKeepsTheCentreValid() {
        let pole = MapView.normalized(Coordinate(latitude: 89, longitude: 10))
        #expect(pole.latitude == TileID.maximumLatitude && pole.longitude == 10)
        let wrapped = MapView.normalized(Coordinate(latitude: 0, longitude: 190))
        #expect(abs(wrapped.longitude - -170) < 1e-9)
        #expect(abs(MapView.normalized(Coordinate(latitude: 0, longitude: -190)).longitude - 170) < 1e-9)
        #expect(MapView.normalized(Coordinate(latitude: 47, longitude: 9.5)) == Coordinate(latitude: 47, longitude: 9.5))
    }
}
