import FeatureStore
import Foundation

/// Finds the divided roads in a scene: pairs of one-way ways side by side, running in opposite directions.
///
/// Two ways are the carriageways of one road when they are of the same class and structure, are one-way (the `oneway` tag, so
/// only the detail band, which holds the tags, has them), their flow runs in opposite directions, and they run side by side
/// with a gap of at most ``maximumGap`` metres between their edges. For every such stretch the result has a strip from the
/// centre line of one to the centre line of the other. Filled in the colour of the road, the strip covers the gap and the inner
/// outlines, and the pair is drawn as one wide road with one outline. A wider divider (grass, a barrier with trees) leaves the
/// two roads apart.
enum DividedRoads {
    /// The widest gap between the edges of two carriageways, in metres, that is still one road.
    static let maximumGap = 6.0
    /// The largest cosine between the flow directions of two carriageways: they must run nearly opposite (within 25 degrees).
    private static let oppositeCosine = -0.9
    /// The distance between samples along a line, in points.
    private static let sampleSpacing = 3.0

    private struct Segment {
        var line: Int
        var ax, ay, bx, by: Double
    }

    private struct Match {
        var partner: Int
        var own: ScreenPoint
        var other: ScreenPoint
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

        var grid: [Int64: [Segment]] = [:]
        func key(_ column: Int, _ row: Int) -> Int64 { (Int64(column) << 32) ^ (Int64(row) & 0xFFFF_FFFF) }
        func cell(_ value: Double) -> Int { Int((value / cellSize).rounded(.down)) }
        for index in candidates {
            let points = lines[index].points
            for position in 0..<(points.count - 1) {
                let a = points[position], b = points[position + 1]
                guard a != b else { continue }
                let segment = Segment(line: index, ax: a.x, ay: a.y, bx: b.x, by: b.y)
                for column in cell(min(a.x, b.x))...cell(max(a.x, b.x)) {
                    for row in cell(min(a.y, b.y))...cell(max(a.y, b.y)) { grid[key(column, row), default: []].append(segment) }
                }
            }
        }

        var strips: [SceneMedian] = []
        for index in candidates {
            let line = lines[index]
            guard let width = widths[index] else { continue }
            var run: [Match] = []
            func finish() {
                if run.count >= 2 {
                    var ring = run.map(\.own)
                    for match in run.reversed() where ring.last != match.other { ring.append(match.other) }
                    if ring.count >= 3 {
                        let centre = run.map { ScreenPoint(x: ($0.own.x + $0.other.x) / 2, y: ($0.own.y + $0.other.y) / 2) }
                        strips.append(SceneMedian(featureClass: line.featureClass, structure: line.structure, ring: ring, centre: centre))
                    }
                }
                run = []
            }
            for (direction, point) in samples(along: line.points) {
                let best = nearest(
                    to: point, direction: direction, flow: flows[index], of: index, lines: lines, flows: flows, widths: widths,
                    ownWidth: width, gapPoints: gapPoints, cellSize: cellSize, grid: grid)
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

    /// The nearest carriageway of another way beside a point: of the same class and structure, flowing the opposite way, within
    /// reach, and with the point opposite the middle of a segment of it, not past its end. Only ways of a higher index count,
    /// so every pair is found once.
    private static func nearest(
        to point: ScreenPoint, direction: (x: Double, y: Double), flow: Int, of own: Int, lines: [SceneLine], flows: [Int],
        widths: [Double?], ownWidth: Double, gapPoints: Double, cellSize: Double, grid: [Int64: [Segment]]
    ) -> Match? {
        func key(_ column: Int, _ row: Int) -> Int64 { (Int64(column) << 32) ^ (Int64(row) & 0xFFFF_FFFF) }
        let column = Int((point.x / cellSize).rounded(.down)), row = Int((point.y / cellSize).rounded(.down))
        var best: (match: Match, distance: Double)?
        for c in (column - 1)...(column + 1) {
            for r in (row - 1)...(row + 1) {
                for segment in grid[key(c, r)] ?? [] where segment.line > own {
                    guard lines[segment.line].featureClass == lines[own].featureClass,
                        lines[segment.line].structure == lines[own].structure, let otherWidth = widths[segment.line]
                    else { continue }
                    let sx = segment.bx - segment.ax, sy = segment.by - segment.ay
                    let length = (sx * sx + sy * sy).squareRoot()
                    guard length > 1e-9 else { continue }
                    let ux = sx / length, uy = sy / length
                    // Opposite flows: the directions of travel, not of the vertices, point against each other.
                    let along = Double(flow * flows[segment.line]) * (direction.x * ux + direction.y * uy)
                    guard along < oppositeCosine else { continue }
                    let t = min(max(((point.x - segment.ax) * sx + (point.y - segment.ay) * sy) / (length * length), 0), 1)
                    let qx = segment.ax + sx * t, qy = segment.ay + sy * t
                    let distance = ((qx - point.x) * (qx - point.x) + (qy - point.y) * (qy - point.y)).squareRoot()
                    guard distance > 1e-6, distance <= (ownWidth + otherWidth) / 2 + gapPoints else { continue }
                    // Beside the point, not beyond the end of the other carriageway.
                    guard abs((qx - point.x) * ux + (qy - point.y) * uy) <= 0.25 * distance + 0.5 else { continue }
                    if best == nil || distance < best!.distance {
                        best = (Match(partner: segment.line, own: point, other: ScreenPoint(x: qx, y: qy)), distance)
                    }
                }
            }
        }
        return best?.match
    }
}
