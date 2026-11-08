import FeatureStore
import Foundation

/// Finds the divided roads in a scene: pairs of one-way ways side by side, running in opposite directions.
///
/// Two ways are the carriageways of one road when they are of the same class and structure, are one-way (the `oneway` tag, or a motorway without one, so
/// only the detail band, which holds the tags, has them), their flow runs in opposite directions, and they run side by side
/// with a steady gap of at most 4 m between their edges (``typicalGap``), and are not named differently. For every such stretch the result has a strip from the
/// centre line of one to the centre line of the other. Filled in the colour of the road, the strip covers the gap and the inner
/// outlines, and the pair is drawn as one wide road with one outline. A wider divider (grass, a barrier with trees) leaves the
/// two roads apart.
enum DividedRoads {
    /// The widest gap, in metres, at which a sample along a carriageway is matched with the other one. It only collects the
    /// stretch; whether the stretch is a divided road is decided on the whole of it (see ``typicalGap``).
    static let maximumGap = 6.0
    /// The gap between the edges, in metres, that the middle value of a stretch must have to be a divided road: not less than
    /// the first (carriageways that touch or overlap are not separated, so they are one road, or a merge), not more than the
    /// second (a wider divider is two roads). A stretch whose gap hovers around one limit is decided once, for all of it, not
    /// sample by sample.
    static let typicalGap = 1.0...4.0
    /// How far the gap of the stretch may vary, in metres, from its smallest to its largest value. A carriageway that merges
    /// with or forks off another has a gap that runs from nothing to the width of a lane or more.
    static let gapVariation = 2.0
    /// The ends of a stretch whose gap differs from the middle value by more than this, in metres, are cut off: the merge or the
    /// fork at the end of a divided road is left as two roads.
    static let endTolerance = 1.5
    /// The shortest stretch, in metres, that is a divided road: shorter ones are the ends of ways that meet at a junction.
    static let minimumLength = 20.0
    /// The largest cosine between the flow directions of two carriageways: they must run nearly opposite (within 25 degrees).
    private static let oppositeCosine = -0.9
    /// The distance between samples along a line, in points.
    private static let sampleSpacing = 3.0

    private struct Match {
        var partner: Int
        var own: ScreenPoint
        var other: ScreenPoint
        /// The distance between the edges of the two carriageways, in points.
        var gap: Double
    }

    /// Finds the strips between carriageways.
    ///
    /// - Parameters:
    ///   - lines: The lines of the scene, all classes.
    ///   - flows: For each line: 1 if the way is one-way in the direction of its vertices, -1 if against it, 0 if it is not
    ///     one-way (or a roundabout, or not a road).
    ///   - widths: The width in points of each line, or `nil` for a line that is not a road.
    ///   - metresPerPoint: The scale of the view.
    /// - Returns: One strip for every stretch where two carriageways run side by side.
    static func medians(lines: [SceneLine], flows: [Int], widths: [Double?], metresPerPoint: Double) -> [SceneMedian] {
        let roadClasses: Set<FeatureClass> = [.roadMajor, .roadMinor]
        var candidates: [Int] = []
        var widest = 0.0
        for index in lines.indices where flows[index] != 0 && lines[index].points.count >= 2 {
            guard let width = widths[index], roadClasses.contains(lines[index].featureClass), lines[index].structure != .tunnel else { continue }
            candidates.append(index)
            widest = max(widest, width)
        }
        guard candidates.count >= 2 else { return [] }
        let gapPoints = maximumGap / max(metresPerPoint, 1e-9)
        let cellSize = max(32.0, widest + gapPoints)

        let context = Context(
            lines: lines, flows: flows, widths: widths, gapPoints: gapPoints,
            grid: CarriagewayGrid(lines: lines, indices: candidates, cellSize: cellSize))

        var strips: [SceneMedian] = []
        let metresPerPoint = max(metresPerPoint, 1e-9)
        for index in candidates {
            let line = lines[index]
            guard let width = widths[index] else { continue }
            var run: [Match] = []
            func finish() {
                defer { run = [] }
                guard run.count >= 2 else { return }
                // The stretch is judged on the whole of it, by its gap in metres: the middle value, the ends cut off where they
                // merge or fork, and the variation of what is left.
                let gaps = run.map { $0.gap * metresPerPoint }
                let middle = gaps.sorted()[gaps.count / 2]
                guard typicalGap.contains(middle) else { return }
                var first = 0, last = run.count - 1
                while first < last, abs(gaps[first] - middle) > endTolerance { first += 1 }
                while last > first, abs(gaps[last] - middle) > endTolerance { last -= 1 }
                let core = Array(run[first...last])
                let coreGaps = gaps[first...last]
                guard let smallest = coreGaps.min(), let largest = coreGaps.max(), largest - smallest <= gapVariation else { return }
                let centre = core.map { ScreenPoint(x: ($0.own.x + $0.other.x) / 2, y: ($0.own.y + $0.other.y) / 2) }
                guard core.count >= 2, length(of: centre) * metresPerPoint >= minimumLength else { return }
                var ring = core.map(\.own)
                for match in core.reversed() where ring.last != match.other { ring.append(match.other) }
                guard ring.count >= 3 else { return }
                strips.append(SceneMedian(featureClass: line.featureClass, structure: line.structure, ring: ring, divider: centre))
            }
            for (direction, point) in samples(along: line.points) {
                let best = nearest(to: point, direction: direction, of: index, ownWidth: width, in: context)
                if let best {
                    if let last = run.last, last.partner != best.partner { finish() }
                    run.append(best)
                } else {
                    finish()
                }
            }
            finish()
        }
        return strips
    }

    private static func length(of points: [ScreenPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    /// The samples along a polyline: the unit direction there, and the point.
    private static func samples(along points: [ScreenPoint]) -> [((x: Double, y: Double), ScreenPoint)] {
        var result: [((x: Double, y: Double), ScreenPoint)] = []
        for position in 0..<(points.count - 1) {
            let a = points[position], b = points[position + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 1e-9 else { continue }
            let count = max(1, Int((length / sampleSpacing).rounded(.up)))
            for step in 0..<count {
                let t = Double(step) / Double(count)
                result.append(((dx / length, dy / length), ScreenPoint(x: a.x + dx * t, y: a.y + dy * t)))
            }
        }
        if let last = points.last, let previous = points.dropLast().last {
            let dx = last.x - previous.x, dy = last.y - previous.y
            let length = (dx * dx + dy * dy).squareRoot()
            if length > 1e-9 { result.append(((dx / length, dy / length), last)) }
        }
        return result
    }

    /// What the search for the carriageway beside a point looks at.
    private struct Context {
        var lines: [SceneLine]
        var flows: [Int]
        var widths: [Double?]
        var gapPoints: Double
        var grid: CarriagewayGrid
    }

    /// The nearest carriageway of another way beside a point: of the same class and structure, flowing the opposite way, within
    /// reach, and with the point opposite the middle of a segment of it, not past its end. Only ways of a higher index count,
    /// so every pair is found once.
    private static func nearest(
        to point: ScreenPoint, direction: (x: Double, y: Double), of own: Int, ownWidth: Double, in context: Context
    ) -> Match? {
        var best: (match: Match, distance: Double)?
        for segment in context.grid.segments(near: point) where segment.line > own {
            let other = context.lines[segment.line]
            guard other.featureClass == context.lines[own].featureClass, other.structure == context.lines[own].structure,
                let otherWidth = context.widths[segment.line]
            else { continue }
            // Two roads that are named, and not the same, are two roads. A carriageway without a name may be one half of a named road.
            if let ownName = context.lines[own].name, let otherName = other.name, ownName != otherName { continue }
            let sx = segment.bx - segment.ax, sy = segment.by - segment.ay
            let length = (sx * sx + sy * sy).squareRoot()
            guard length > 1e-9 else { continue }
            let ux = sx / length, uy = sy / length
            // Opposite flows: the directions of travel, not of the vertices, point against each other.
            let along = Double(context.flows[own] * context.flows[segment.line]) * (direction.x * ux + direction.y * uy)
            guard along < oppositeCosine else { continue }
            let t = min(max(((point.x - segment.ax) * sx + (point.y - segment.ay) * sy) / (length * length), 0), 1)
            let qx = segment.ax + sx * t, qy = segment.ay + sy * t
            let distance = ((qx - point.x) * (qx - point.x) + (qy - point.y) * (qy - point.y)).squareRoot()
            guard distance > 1e-6, distance <= (ownWidth + otherWidth) / 2 + context.gapPoints else { continue }
            // Beside the point, not beyond the end of the other carriageway.
            guard abs((qx - point.x) * ux + (qy - point.y) * uy) <= 0.25 * distance + 0.5 else { continue }
            if best == nil || distance < best!.distance {
                best = (
                    Match(
                        partner: segment.line, own: point, other: ScreenPoint(x: qx, y: qy),
                        gap: distance - (ownWidth + otherWidth) / 2),
                    distance)
            }
        }
        return best?.match
    }
}
