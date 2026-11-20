import FeatureStore
import Foundation
import GeoCore
import MapRender
import MapStyle
import Testing
import TrackMatching

@testable import TrackOverlays

@Suite("Heat map overlay")
struct HeatMapOverlayTests {
    /// A way along 60 N from 10.000 E in steps of 0.005 degrees (about 278 m), as the vertices say.
    private func network(_ ways: [(Int64, [Double])]) -> LineNetwork {
        LineNetwork(
            features: ways.map { id, longitudes in
                StoredFeature(
                    classID: FeatureClass.path.rawValue, kind: .line, objectType: .way, objectID: id,
                    parts: [GeometryPart(points: longitudes.map { PackedPoint(longitude: Int32(($0 * 1e7).rounded()), latitude: 600_000_000) })])
            })
    }

    private func viewport(zoom: Double = 14, longitude: Double = 10.005) -> MapViewport {
        MapViewport(center: Coordinate(latitude: 60, longitude: longitude), zoom: zoom, width: 400, height: 300)
    }

    private func lines(_ items: [OverlayItem]) -> [OverlayLine] { items.compactMap { if case .line(let line) = $0 { line } else { nil } } }

    private let way = [10.0, 10.005, 10.01]

    @Test("The line of a range follows the way, cut inside an edge and joined across the edges")
    func rangeLines() {
        let ways = HeatMapWays(network: network([(1, way)]))
        let parts = ways.lines(way: 1, from: 100, to: 400)
        #expect(parts.count == 1 && parts[0].count == 3, "a point where the way has a vertex")
        // 100 m and 400 m from the start: 0.0018 and 0.0072 degrees of longitude at 60 N (1 degree is 55.6 km).
        #expect(abs(parts[0][0].longitude - (10 + 100 / 55_597.0)) < 2e-5 && abs(parts[0][2].longitude - (10 + 400 / 55_597.0)) < 2e-5)
        #expect(ways.lines(way: 1, from: 100, to: 100).isEmpty && ways.lines(way: 2, from: 0, to: 100).isEmpty)
        #expect(ways.lines(way: 1, from: 5_000, to: 6_000).isEmpty, "beyond the end of the way")
        #expect(ways.contains(way: 1) && !ways.contains(way: 2))
    }

    @Test("Where the network has no edge for a stretch of the way the line is cut")
    func gapInTheWay() {
        // Two pieces of one way, with 100 m between them (the offsets of the second say so).
        let first = StoredFeature(
            classID: FeatureClass.path.rawValue, kind: .line, objectType: .way, objectID: 1,
            parts: [GeometryPart(points: [PackedPoint(longitude: 100_000_000, latitude: 600_000_000), PackedPoint(longitude: 100_050_000, latitude: 600_000_000)])])
        let second = StoredFeature(
            classID: FeatureClass.path.rawValue, kind: .line, objectType: .way, objectID: 1, offsetAlongLine: 40_000,
            parts: [GeometryPart(points: [PackedPoint(longitude: 100_100_000, latitude: 600_000_000), PackedPoint(longitude: 100_150_000, latitude: 600_000_000)])])
        let ways = HeatMapWays(network: LineNetwork(features: [first, second]))
        #expect(ways.lines(way: 1, from: 0, to: 600).count == 2)
    }

    @Test("Buckets that follow each other on one step are one line; another step, or a hole, makes another")
    func runs() {
        let ways = HeatMapWays(network: network([(1, way)]))
        let buckets = [0, 1, 2, 3].map { HeatMapBucket(wayID: 1, bucket: $0, count: 1) } + [HeatMapBucket(wayID: 1, bucket: 4, count: 5)]
            + [HeatMapBucket(wayID: 1, bucket: 8, count: 5), HeatMapBucket(wayID: 1, bucket: 9, count: 0)]
        let overlay = HeatMapOverlay(buckets: buckets, ways: ways)
        #expect(overlay.runCount == 3, "buckets 0 to 3 on the first step, 4 on the third, 8 on the third after a hole")
    }

    @Test("A count has the look of its step, from the fixed scale, whatever the other counts are")
    func scaleIsFixed() {
        let ways = HeatMapWays(network: network([(1, way)]))
        let one = HeatMapOverlay(buckets: [HeatMapBucket(wayID: 1, bucket: 0, count: 3)], ways: ways)
        let busy = HeatMapOverlay(buckets: [HeatMapBucket(wayID: 1, bucket: 0, count: 3), HeatMapBucket(wayID: 1, bucket: 30, count: 500)], ways: ways)
        let a = lines(one.items(for: viewport())), b = lines(busy.items(for: viewport()))
        #expect(a.count == 1 && b.count == 2)
        #expect(a[0].style == HeatMapScale.standard.steps[1].style && b.contains { $0.style == a[0].style })
        #expect(b.last?.style == HeatMapScale.standard.steps[4].style, "the busiest is drawn last")
    }

    @Test("Counts below the first step, unknown ways and negative buckets are not drawn")
    func notDrawn() {
        let ways = HeatMapWays(network: network([(1, way)]))
        let scale = HeatMapScale(steps: [.init(minimumCount: 5, style: OverlayLineStyle(color: .init(red: 1, green: 0, blue: 0), width: 3))])
        let overlay = HeatMapOverlay(
            buckets: [HeatMapBucket(wayID: 1, bucket: 0, count: 4), HeatMapBucket(wayID: 9, bucket: 0, count: 50), HeatMapBucket(wayID: 1, bucket: -1, count: 50)],
            ways: ways, scale: scale)
        #expect(overlay.runCount == 0 && overlay.items(for: viewport()).isEmpty)
        #expect(HeatMapScale(steps: []) == HeatMapScale.standard)
    }

    @Test("Lines are in screen points where the way is, and a run outside the view costs no item")
    func viewportClipping() {
        let ways = HeatMapWays(network: network([(1, way)]))
        let overlay = HeatMapOverlay(buckets: (0..<50).map { HeatMapBucket(wayID: 1, bucket: $0, count: 1) }, ways: ways)
        let items = lines(overlay.items(for: viewport()))
        #expect(items.count == 1 && items[0].points.count == 3)
        // The view is centred on the middle of the way (10.005), so the line crosses the middle of the screen.
        #expect(items[0].points.map(\.y).allSatisfy { abs($0 - 150) < 1 } && items[0].points[1].x > 100 && items[0].points[1].x < 300)
        #expect(overlay.items(for: viewport(longitude: 11)).isEmpty, "a view a degree away")
    }

    @Test("A way that is long on the screen is cut to the view: a frame costs about the same at every zoom")
    func zoomedIn() {
        let ways = HeatMapWays(network: network([(1, way)]))
        let overlay = HeatMapOverlay(buckets: (0..<50).map { HeatMapBucket(wayID: 1, bucket: $0, count: 1) }, ways: ways)
        let items = lines(overlay.items(for: viewport(zoom: 20)))
        #expect(items.count == 1 && items[0].points.allSatisfy { $0.x >= -20 && $0.x <= 420 })
    }
}
