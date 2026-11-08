import FeatureStore
import Foundation

/// One sample on a line: where it is, in degrees (as stored) and in metres, and which way the line runs.
struct LineSample {
    var point: PackedPoint
    var x: Double
    var y: Double
    /// The unit direction of the segment the sample lies on, in metres.
    var directionX: Double
    var directionY: Double
}

/// Cuts a line into stretches that a test says apart, such as the part in the sea and the part on land.
///
/// The test is made at the middle of every piece of at most `spacing` metres, so the cut is at most half a spacing from the
/// place where the answer really changes. The cut points lie on the segments, so the stretches together are the line.
enum LineSplitter {
    private static let projection = LocalMetres()

    /// Splits a line.
    ///
    /// - Parameters:
    ///   - line: The points of the line, at least two.
    ///   - spacing: The longest piece, in metres, that gets one answer.
    ///   - test: The answer for a sample.
    /// - Returns: The stretches in order, each with its answer; neighbours have different answers.
    static func split(_ line: [PackedPoint], spacing: Double, test: (LineSample) -> Bool) -> [(answer: Bool, points: [PackedPoint])] {
        var stretches: [(answer: Bool, points: [PackedPoint])] = []
        guard line.count >= 2 else { return stretches }
        for index in 0..<(line.count - 1) {
            let a = line[index], b = line[index + 1]
            let pa = projection.project(a), pb = projection.project(b)
            let dx = pb.x - pa.x, dy = pb.y - pa.y
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 0 else { continue }
            let count = max(1, Int((length / spacing).rounded(.up)))
            for step in 0..<count {
                let t0 = Double(step) / Double(count), t1 = Double(step + 1) / Double(count), middle = (t0 + t1) / 2
                let sample = LineSample(
                    point: interpolate(a, b, middle), x: pa.x + dx * middle, y: pa.y + dy * middle,
                    directionX: dx / length, directionY: dy / length)
                let answer = test(sample)
                let start = step == 0 ? a : interpolate(a, b, t0)
                if let last = stretches.last, last.answer == answer {
                    // The same answer: the stretch goes on, and only the real vertex at the end of a segment is a point of it.
                    if step == count - 1 { stretches[stretches.count - 1].points.append(b) }
                } else {
                    // The answer changes here: the stretch before ends, and the next begins, at the same point.
                    if let last = stretches.last, last.points.last != start { stretches[stretches.count - 1].points.append(start) }
                    stretches.append((answer, step == count - 1 ? [start, b] : [start]))
                }
            }
        }
        return stretches
    }

    /// The stretches of some lines for which a test says no, and how many stretches it said yes to.
    ///
    /// - Parameters:
    ///   - lines: The lines.
    ///   - spacing: See ``split(_:spacing:test:)``.
    ///   - drop: Whether a sample is to be left out.
    /// - Returns: The stretches kept, and the number of stretches left out.
    static func removing(
        from lines: [[PackedPoint]], spacing: Double, where drop: (LineSample) -> Bool
    ) -> (kept: [[PackedPoint]], dropped: Int) {
        var kept: [[PackedPoint]] = []
        var dropped = 0
        for line in lines {
            for stretch in split(line, spacing: spacing, test: drop) {
                if stretch.answer { dropped += 1 } else if stretch.points.count >= 2 { kept.append(stretch.points) }
            }
        }
        return (kept, dropped)
    }

    private static func interpolate(_ a: PackedPoint, _ b: PackedPoint, _ t: Double) -> PackedPoint {
        PackedPoint(
            longitude: Int32((Double(a.longitude) + (Double(b.longitude) - Double(a.longitude)) * t).rounded()),
            latitude: Int32((Double(a.latitude) + (Double(b.latitude) - Double(a.latitude)) * t).rounded()))
    }
}
