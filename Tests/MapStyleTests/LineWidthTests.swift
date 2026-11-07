import Testing

@testable import MapStyle

@Suite("LineWidth and lanes")
struct LineWidthTests {
    private let road = LineWidth(
        points: ZoomValue((12, 1.0), (16, 3.0)), ground: GroundWidth(metresPerLane: 3, defaultLanes: 2))

    @Test func screenWidthWinsWhenZoomedOut() {
        // 100 m per point: even 4 lanes (12 m) are far below the legible width.
        #expect(road.resolved(atZoom: 12, metresPerPoint: 100, lanes: 4) == 1)
    }

    @Test func lanesWidenTheRoadWhenZoomedIn() {
        // 0.5 m per point: 2 lanes = 6 m = 12 pt, 4 lanes = 12 m = 24 pt.
        #expect(road.resolved(atZoom: 18, metresPerPoint: 0.5, lanes: 2) == 12)
        #expect(road.resolved(atZoom: 18, metresPerPoint: 0.5, lanes: 4) == 24)
    }

    @Test func missingOrInvalidLanesUseTheDefault() {
        let expected = road.resolved(atZoom: 18, metresPerPoint: 0.5, lanes: 2)
        #expect(road.resolved(atZoom: 18, metresPerPoint: 0.5, lanes: nil) == expected)
        #expect(road.resolved(atZoom: 18, metresPerPoint: 0.5, lanes: 0) == expected)
        #expect(road.resolved(atZoom: 18, metresPerPoint: 0.5, lanes: -3) == expected)
    }

    @Test func absurdLaneCountsAreCapped() {
        // 99 lanes is capped at 12 lanes = 36 m = 72 pt at 0.5 m per point.
        #expect(road.resolved(atZoom: 18, metresPerPoint: 0.5, lanes: 99) == 72)
    }

    @Test func lineWithoutGroundWidthKeepsItsScreenWidth() {
        let path = LineWidth(points: ZoomValue((12, 1.0), (16, 2.0)))
        #expect(path.resolved(atZoom: 18, metresPerPoint: 0.01, lanes: 4) == 2)
    }

    @Test func badScaleFallsBackToTheScreenWidth() {
        #expect(road.resolved(atZoom: 14, metresPerPoint: 0, lanes: 4) == 2)
        #expect(road.resolved(atZoom: 14, metresPerPoint: .infinity, lanes: 4) == 2)
        #expect(road.resolved(atZoom: 14, metresPerPoint: .nan, lanes: 4) == 2)
    }
}
