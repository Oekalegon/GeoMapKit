import FeatureStore
import Foundation

/// Finds the ends where one road continues into another of a different width, so the renderer can blend the widths.
///
/// A road is drawn at the width of its own `lanes` tag. Where the lane count changes at a node (a road divides into
/// carriageways, a lane ends before a bridge) the two ways meet with a step in width. The renderer blends that step over
/// a short stretch of each way; this type decides which ends get a blend and what width they blend to: the mean of the two
/// widths, so both ways agree at the node.
enum RoadTaper {
    /// Roads that leave a node within this angle of straight on the other side are taken to continue each other: the cosine
    /// of 140 degrees. A side road leaves at a much smaller angle and is not a continuation.
    private static let continuationCosine = -0.766
    /// A road that meets a straight-through pair of ways ends flat, unless it leaves within this angle of one of them (a fork
    /// rather than a side road): the cosine of 35 degrees.
    private static let forkCosine = 0.82
    /// A difference in width below this many points is not worth a blend.
    private static let minimumDifference = 0.75

    struct Entry {
        var line: Int
        var isStart: Bool
        var direction: (x: Double, y: Double)
        var width: Double
    }

    /// Sets ``SceneLine/startWidth`` and ``SceneLine/endWidth`` on the lines that need a blend.
    ///
    /// - Parameters:
    ///   - lines: The lines of all classes; the changes are made in place.
    ///   - nodes: The stored points of the first and last vertex of each line, which say which ends meet.
    ///   - widths: The width in points of each line, or `nil` for a line that is not a road.
    static func apply(to lines: inout [SceneLine], nodes: [(start: PackedPoint?, end: PackedPoint?)], widths: [Double?]) {
        var atNode: [PackedPoint: [Entry]] = [:]
        for index in lines.indices {
            guard let width = widths[index], lines[index].points.count >= 2 else { continue }
            let points = lines[index].points
            if let node = nodes[index].start, let direction = unit(from: points[0], to: points[1]) {
                atNode[node, default: []].append(Entry(line: index, isStart: true, direction: direction, width: width))
            }
            if let node = nodes[index].end, let direction = unit(from: points[points.count - 1], to: points[points.count - 2]) {
                atNode[node, default: []].append(Entry(line: index, isStart: false, direction: direction, width: width))
            }
        }
        for entries in atNode.values where entries.count >= 3 {
            markSideRoads(among: entries, in: &lines)
        }
        for entries in atNode.values where entries.count >= 2 {
            for entry in entries {
                // The partner is the road of the same class that leaves most nearly straight on the other side.
                var best: (entry: Entry, dot: Double)?
                for other in entries where other.line != entry.line && lines[other.line].featureClass == lines[entry.line].featureClass {
                    let dot = entry.direction.x * other.direction.x + entry.direction.y * other.direction.y
                    if dot < continuationCosine, best.map({ dot < $0.dot }) ?? true { best = (other, dot) }
                }
                guard let partner = best?.entry, abs(partner.width - entry.width) >= minimumDifference else { continue }
                let target = (partner.width + entry.width) / 2
                if entry.isStart { lines[entry.line].startWidth = target } else { lines[entry.line].endWidth = target }
            }
        }
    }

    /// Marks the ends of the roads that meet a straight-through pair of ways side on.
    ///
    /// A through road that is cut into two ways at a junction ends both halves at the node, so the side road that ends there
    /// meets no vertex in the middle of a road, and is not found as a T junction by the scene builder. Here the two halves are
    /// the pair of ends that leave in nearly opposite directions; any other end at the node that is not almost one of
    /// their directions (a fork) is a side road, and ends flat.
    private static func markSideRoads(among entries: [Entry], in lines: inout [SceneLine]) {
        var pair: (a: Entry, b: Entry, dot: Double)?
        for (index, first) in entries.enumerated() {
            for second in entries[(index + 1)...] where second.line != first.line {
                let dot = first.direction.x * second.direction.x + first.direction.y * second.direction.y
                if dot < continuationCosine, pair.map({ dot < $0.dot }) ?? true { pair = (first, second, dot) }
            }
        }
        guard let pair else { return }
        func cosine(_ a: Entry, _ b: Entry) -> Double { a.direction.x * b.direction.x + a.direction.y * b.direction.y }
        for entry in entries where entry.line != pair.a.line && entry.line != pair.b.line {
            guard cosine(entry, pair.a) < forkCosine, cosine(entry, pair.b) < forkCosine else { continue }
            if entry.isStart { lines[entry.line].flatStart = true } else { lines[entry.line].flatEnd = true }
        }
    }

    private static func unit(from a: ScreenPoint, to b: ScreenPoint) -> (x: Double, y: Double)? {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        return length > 1e-9 ? (dx / length, dy / length) : nil
    }
}
