import FeatureStore
import Foundation
import OSMPBF

/// The roads of an extract in a grid, for asking whether a footway runs beside one.
///
/// A sidewalk is mapped as a `highway=footway` that runs along a road at a few metres, often without a `footway=sidewalk`
/// tag. A footway through a park or along a trail does not. The difference is geometry: a footway is taken to be a sidewalk
/// when most of its length lies within ``maximumDistance`` of a road and runs the same way (within about 25 degrees), so a
/// footway that crosses a road or ends at it does not count for the stretch where it meets it.
///
/// Positions are turned into metres with ``LocalMetres``. Only roads count (`roadMajor` and `roadMinor` that are not
/// pedestrian streets and not tunnels).
struct RoadIndex {
    /// The farthest a footway may be from a road, in metres, to be beside it.
    static let maximumDistance = 15.0
    /// The smallest cosine of the angle between a footway and a road for them to run the same way (25 degrees).
    static let minimumCosine = 0.906
    /// The share of the footway's length that must be beside a road.
    static let minimumShare = 0.6
    /// A footway shorter than this, in metres, is not judged.
    static let minimumLength = 10.0
    /// The spacing of the points tested along a footway, in metres.
    private static let sampleSpacing = 5.0

    private struct Segment {
        var x0, y0, x1, y1: Double
    }

    private let projection: LocalMetres
    private var grid: [Int64: [Segment]] = [:]

    /// Builds the index from the ways of an extract.
    ///
    /// - Parameters:
    ///   - extract: The extract.
    ///   - classifier: The classifier that says which ways are roads.
    init(extract: OSMExtract, classifier: FeatureClassifier) {
        projection = LocalMetres()
        for position in extract.ways.indices {
            let tags = extract.ways.tags(at: position)
            guard tags.value(forKey: "highway") != nil, tags.value(forKey: "highway") != "pedestrian" else { continue }
            let classification = classifier.classify(tags, shape: .openWay)
            guard classification.featureClass == .roadMajor || classification.featureClass == .roadMinor,
                !SubclassBits.isTunnel(classification.subclass)
            else { continue }
            let (runs, _) = FeatureStoreBuilder.runs(ofWayAt: position, in: extract)
            for run in runs {
                for index in 0..<(run.count - 1) { add(project(run[index]), project(run[index + 1])) }
            }
        }
    }

    /// Whether most of a footway lies beside a road.
    ///
    /// - Parameter runs: The footway's points, one array per piece (a way with a gap has two).
    /// - Returns: `true` if the footway is long enough to judge and enough of it runs beside a road.
    func isBesideARoad(_ runs: [[PackedPoint]]) -> Bool {
        var total = 0.0, beside = 0.0
        for run in runs where run.count >= 2 {
            for index in 0..<(run.count - 1) {
                let a = project(run[index]), b = project(run[index + 1])
                let dx = b.x - a.x, dy = b.y - a.y
                let length = (dx * dx + dy * dy).squareRoot()
                guard length > 0 else { continue }
                let samples = max(1, Int((length / Self.sampleSpacing).rounded(.up)))
                let weight = length / Double(samples)
                for sample in 0..<samples {
                    let t = (Double(sample) + 0.5) / Double(samples)
                    total += weight
                    if isNearARoad(x: a.x + dx * t, y: a.y + dy * t, directionX: dx / length, directionY: dy / length) {
                        beside += weight
                    }
                }
            }
        }
        return total >= Self.minimumLength && beside >= Self.minimumShare * total
    }

    // MARK: Grid

    private func project(_ point: PackedPoint) -> (x: Double, y: Double) { projection.project(point) }

    private static func key(_ column: Int, _ row: Int) -> Int64 { (Int64(column) << 32) ^ (Int64(row) & 0xFFFF_FFFF) }

    private static func cell(_ value: Double) -> Int { Int((value / maximumDistance).rounded(.down)) }

    private mutating func add(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) {
        let segment = Segment(x0: a.x, y0: a.y, x1: b.x, y1: b.y)
        for column in Self.cell(min(a.x, b.x))...Self.cell(max(a.x, b.x)) {
            for row in Self.cell(min(a.y, b.y))...Self.cell(max(a.y, b.y)) { grid[Self.key(column, row), default: []].append(segment) }
        }
    }

    private func isNearARoad(x: Double, y: Double, directionX: Double, directionY: Double) -> Bool {
        let column = Self.cell(x), row = Self.cell(y)
        for c in (column - 1)...(column + 1) {
            for r in (row - 1)...(row + 1) {
                for segment in grid[Self.key(c, r)] ?? [] {
                    let sx = segment.x1 - segment.x0, sy = segment.y1 - segment.y0
                    let squared = sx * sx + sy * sy
                    guard squared > 0 else { continue }
                    let t = min(max(((x - segment.x0) * sx + (y - segment.y0) * sy) / squared, 0), 1)
                    let px = segment.x0 + t * sx - x, py = segment.y0 + t * sy - y
                    guard px * px + py * py <= Self.maximumDistance * Self.maximumDistance else { continue }
                    let cosine = abs(directionX * sx + directionY * sy) / squared.squareRoot()
                    if cosine >= Self.minimumCosine { return true }
                }
            }
        }
        return false
    }
}
