import Foundation
import Testing

@testable import TrackOverlays

@Suite("Route simplifier")
struct RouteSimplifierTests {
    @Test("A straight line is reduced to its ends, a corner is kept")
    func straightAndCorner() {
        let x = [0.0, 1, 2, 3, 4], y = [0.0, 0, 0, 0, 0]
        #expect(RouteSimplifier.keep(x: x, y: y, in: 0..<5, tolerance: 0.1) == [0, 4])
        let cornerX = [0.0, 1, 2, 2, 2], cornerY = [0.0, 0, 0, 1, 2]
        #expect(RouteSimplifier.keep(x: cornerX, y: cornerY, in: 0..<5, tolerance: 0.1) == [0, 2, 4])
    }

    @Test("Short ranges are returned as they are, and a range inside a longer array works on its own points")
    func ranges() {
        #expect(RouteSimplifier.keep(x: [0, 1], y: [0, 5], in: 0..<2, tolerance: 1) == [0, 1])
        #expect(RouteSimplifier.keep(x: [0], y: [0], in: 0..<1, tolerance: 1) == [0])
        #expect(RouteSimplifier.keep(x: [], y: [], in: 0..<0, tolerance: 1).isEmpty)
        // Two polylines in one array: the second is 3...7, and the point 2 is not touched by it.
        let x = [0.0, 1, 2, 3, 4, 5, 6, 7], y = [0.0, 9, 0, 0, 0, 0, 0, 0]
        #expect(RouteSimplifier.keep(x: x, y: y, in: 3..<8, tolerance: 0.1) == [3, 7])
    }

    @Test("No dropped point is farther from the simplified line than the tolerance")
    func withinTheTolerance() {
        var x: [Double] = [], y: [Double] = []
        for index in 0..<2_000 {
            x.append(Double(index) * 0.7)
            y.append(30 * sin(Double(index) / 40) + Double((index * 7919) % 13) / 13)
        }
        let tolerance = 0.5
        let kept = RouteSimplifier.keep(x: x, y: y, in: 0..<2_000, tolerance: tolerance)
        #expect(kept.first == 0 && kept.last == 1_999 && kept.count < 2_000 && kept == kept.sorted())
        for index in 0..<2_000 {
            var best = Double.infinity
            for (a, b) in zip(kept, kept.dropFirst()) where a <= index && index <= b {
                let dx = x[b] - x[a], dy = y[b] - y[a]
                let t = max(0, min(1, ((x[index] - x[a]) * dx + (y[index] - y[a]) * dy) / (dx * dx + dy * dy)))
                best = min(best, ((x[index] - x[a] - t * dx) * (x[index] - x[a] - t * dx) + (y[index] - y[a] - t * dy) * (y[index] - y[a] - t * dy)).squareRoot())
            }
            #expect(best <= tolerance + 1e-9, "point \(index) is \(best) away")
        }
    }

    @Test("A route of a million points is simplified without a deep stack")
    func manyPoints() {
        let count = 1_000_000
        let x = (0..<count).map { Double($0) }
        let y = (0..<count).map { sin(Double($0) / 5_000) * 100 }
        let kept = RouteSimplifier.keep(x: x, y: y, in: 0..<count, tolerance: 0.5)
        #expect(kept.count < count / 10 && kept.first == 0 && kept.last == count - 1)
    }
}
