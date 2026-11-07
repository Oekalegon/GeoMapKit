import FeatureStore
import Foundation

/// Assembles the member ways of a `type=multipolygon` relation into polygons with holes.
///
/// Outer and inner ways are joined separately into rings (see ``RingJoiner``). Each
/// inner ring goes to the smallest outer ring that contains it. The result is all or
/// nothing: if the extract flags the relation as incomplete, a member way or node is
/// missing, or any ring does not close, no polygon is produced. The joined rings and
/// chains come back as ``MultipolygonAssembly/outlines`` instead, to draw as lines and
/// never to fill, because an open ring would force a guess about the inside.
///
/// Problems that leave the polygons valid (inner rings without an outer ring, rings with
/// no area) are counted in the ``AssemblyReport``. Self-intersecting rings are not
/// detected or repaired; the even-odd fill degrades mildly there.
enum MultipolygonAssembler {
    /// Assembles one relation.
    ///
    /// - Parameters:
    ///   - members: The way members. Members that are not ways must be left out by the caller.
    ///   - relationIsComplete: The extract's flag: whether all members of the relation are present.
    static func assemble(members: [MultipolygonMember], relationIsComplete: Bool) -> MultipolygonAssembly {
        var report = AssemblyReport()
        var outerWays: [RingJoiner.Way] = []
        var innerWays: [RingJoiner.Way] = []
        var seen = Set<Pair>()
        var sawOuter = false
        for member in members {
            guard member.role != .ignored else { continue }
            guard seen.insert(Pair(id: member.wayID, inner: member.role == .inner)).inserted else {
                report.duplicateMembers += 1
                continue
            }
            if member.role == .outer { sawOuter = true }
            guard let points = member.points, points.count == member.nodeIDs.count else {
                report.missingMembers += 1
                continue
            }
            let way = RingJoiner.Way(id: member.wayID, nodeIDs: member.nodeIDs, points: points)
            if member.role == .outer { outerWays.append(way) } else { innerWays.append(way) }
        }

        let outer = RingJoiner.join(outerWays)
        let inner = RingJoiner.join(innerWays)
        report.unclosedChains = outer.chains.count + inner.chains.count
        report.degenerateRings = outer.degenerate + inner.degenerate

        var outerRings = outer.rings.compactMap(Ring.init)
        var innerRings = inner.rings.compactMap(Ring.init)
        report.degenerateRings += (outer.rings.count - outerRings.count) + (inner.rings.count - innerRings.count)

        let complete = relationIsComplete && report.missingMembers == 0 && report.unclosedChains == 0 && sawOuter
            && !outerRings.isEmpty
        guard complete else {
            let rings = (outer.rings + outer.chains + inner.rings + inner.chains)
            return MultipolygonAssembly(isComplete: false, polygons: [], outlines: rings, report: report)
        }

        // Orientation: outer counter-clockwise, inner clockwise, in Web Mercator.
        for index in outerRings.indices where outerRings[index].signedArea < 0 { outerRings[index].reverse() }
        for index in innerRings.indices where innerRings[index].signedArea > 0 { innerRings[index].reverse() }

        var holes = [[Ring]](repeating: [], count: outerRings.count)
        let bySize = outerRings.indices.sorted { abs(outerRings[$0].signedArea) < abs(outerRings[$1].signedArea) }
        for inner in innerRings {
            if let owner = bySize.first(where: { outerRings[$0].contains(inner) }) {
                holes[owner].append(inner)
            } else {
                report.orphanInnerRings += 1
            }
        }
        let polygons = outerRings.indices.map { index in
            AssembledPolygon(outer: outerRings[index].points, inners: holes[index].map(\.points))
        }
        return MultipolygonAssembly(isComplete: true, polygons: polygons, outlines: [], report: report)
    }

    /// Whether an old-style multipolygon takes its tags from its outer way.
    ///
    /// In old data the tags sit on the single outer way and the relation has only `type`.
    /// The caller then classifies with the way's tags and does not emit the way separately.
    ///
    /// - Parameters:
    ///   - relationKeys: The keys of the relation's tags.
    ///   - outerWayCount: The number of outer way members.
    static func adoptsOuterWayTags(relationKeys: [String], outerWayCount: Int) -> Bool {
        outerWayCount == 1 && relationKeys.allSatisfy { $0 == "type" }
    }

    private struct Pair: Hashable {
        let id: Int64
        let inner: Bool
    }

    /// A closed ring in Web Mercator for orientation and containment tests.
    private struct Ring {
        var points: [PackedPoint]
        private var xs: [Double]
        private var ys: [Double]
        private(set) var signedArea: Double

        /// - Returns: `nil` for a ring with fewer than four points or no area.
        init?(_ points: [PackedPoint]) {
            guard points.count >= 4, points.first == points.last else { return nil }
            self.points = points
            xs = points.map { Double($0.longitude) }
            ys = points.map { Mercator.y(latitude: Double($0.latitude)) }
            signedArea = 0
            signedArea = Self.area(xs, ys)
            if abs(signedArea) < 1e-12 { return nil }
        }

        mutating func reverse() {
            points.reverse()
            xs.reverse()
            ys.reverse()
            signedArea = -signedArea
        }

        /// Whether most of the other ring's vertices lie inside this ring. Vertices shared with this ring are ignored.
        func contains(_ other: Ring) -> Bool {
            let shared = Set(points)
            var inside = 0, outside = 0
            for index in 0..<(other.points.count - 1) where !shared.contains(other.points[index]) {
                if contains(x: other.xs[index], y: other.ys[index]) { inside += 1 } else { outside += 1 }
            }
            return inside > outside
        }

        private func contains(x: Double, y: Double) -> Bool {
            var inside = false
            var j = xs.count - 1
            for i in 0..<xs.count {
                if (ys[i] > y) != (ys[j] > y), x < (xs[j] - xs[i]) * (y - ys[i]) / (ys[j] - ys[i]) + xs[i] { inside.toggle() }
                j = i
            }
            return inside
        }

        /// The signed area in lon/lat units times radians; positive for counter-clockwise rings.
        private static func area(_ xs: [Double], _ ys: [Double]) -> Double {
            var sum = 0.0
            for index in 0..<(xs.count - 1) {
                sum += (xs[index] - xs[0]) * (ys[index + 1] - ys[0]) - (xs[index + 1] - xs[0]) * (ys[index] - ys[0])
            }
            return sum / 2
        }
    }
}
