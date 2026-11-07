import FeatureStore
import Foundation
import Testing

@testable import FeatureStoreBuilder

@Suite("Simplification")
struct GeometrySimplifierTests {
    let block = Block()
    // Half a pixel at the top of the overview band.
    let tolerance = GeometrySimplifier.tolerance(for: .overview)!

    private func distance(_ point: PackedPoint, toLine line: [PackedPoint]) -> Double {
        func project(_ p: PackedPoint) -> (Double, Double) { (Mercator.radians(longitude: Double(p.longitude)), Mercator.y(latitude: Double(p.latitude))) }
        let (px, py) = project(point)
        var best = Double.infinity
        for (a, b) in zip(line, line.dropFirst()) {
            let (ax, ay) = project(a), (bx, by) = project(b)
            let dx = bx - ax, dy = by - ay
            let t = dx * dx + dy * dy == 0 ? 0 : max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
            best = min(best, hypot(px - (ax + t * dx), py - (ay + t * dy)))
        }
        return best
    }

    @Test("Collinear points collapse and the end points stay")
    func collinear() {
        let line = (0...10).map { block.point(0.5 + Double($0) * 0.2, 1.0) }
        let result = GeometrySimplifier.simplify(line: line, tolerance: tolerance)
        #expect(result == [line.first!, line.last!])
    }

    @Test("Short input is returned unchanged")
    func short() {
        #expect(GeometrySimplifier.simplify(line: [], tolerance: tolerance).isEmpty)
        let two = [block.point(1, 1), block.point(2, 2)]
        #expect(GeometrySimplifier.simplify(line: two, tolerance: tolerance) == two)
    }

    @Test("A corner that is larger than the tolerance is kept")
    func keepsCorner() {
        let line = [block.point(0.5, 1), block.point(1.5, 1), block.point(1.5, 2)]
        #expect(GeometrySimplifier.simplify(line: line, tolerance: tolerance) == line)
    }

    @Test("Every removed vertex is within the tolerance of the result")
    func withinTolerance() {
        var generator = SplitMix64(seed: 3)
        for _ in 0..<100 {
            var line: [PackedPoint] = []
            var x = 0.2, y = 1.5
            for _ in 0..<200 {
                x += Double.random(in: 0.002...0.012, using: &generator)
                y += Double.random(in: -0.01...0.01, using: &generator)
                line.append(block.point(x, y))
            }
            let result = GeometrySimplifier.simplify(line: line, tolerance: tolerance)
            #expect(result.count <= line.count && result.first == line.first && result.last == line.last)
            for vertex in line { #expect(distance(vertex, toLine: result) <= tolerance * 1.0001) }
            #expect(GeometrySimplifier.simplify(line: line, tolerance: tolerance) == result)
        }
    }

    @Test("A ring keeps at least three distinct vertices or disappears")
    func rings() throws {
        let big = [block.point(1, 1), block.point(2, 1), block.point(2, 2), block.point(1, 2), block.point(1, 1)]
        #expect(GeometrySimplifier.simplify(ring: big, tolerance: tolerance) == big)
        let withBump = [block.point(1, 1), block.point(1.5, 1.0000001), block.point(2, 1), block.point(2, 2), block.point(1, 2), block.point(1, 1)]
        let simplified = try #require(GeometrySimplifier.simplify(ring: withBump, tolerance: tolerance))
        #expect(simplified.count == 5 && simplified.first == simplified.last)
        // A ring smaller than the tolerance collapses.
        let tiny = [PackedPoint(longitude: 90_000_000, latitude: 470_000_000), PackedPoint(longitude: 90_000_010, latitude: 470_000_000), PackedPoint(longitude: 90_000_010, latitude: 470_000_010), PackedPoint(longitude: 90_000_000, latitude: 470_000_000)]
        #expect(GeometrySimplifier.simplify(ring: tiny, tolerance: tolerance) == nil)
        #expect(GeometrySimplifier.simplify(ring: [block.point(1, 1)], tolerance: tolerance) == nil)
    }
}
