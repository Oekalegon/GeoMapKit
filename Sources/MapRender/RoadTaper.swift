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

    private static func unit(from a: ScreenPoint, to b: ScreenPoint) -> (x: Double, y: Double)? {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        return length > 1e-9 ? (dx / length, dy / length) : nil
    }
}
