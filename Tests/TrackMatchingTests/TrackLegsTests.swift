import FeatureStore
import Foundation
import GeoCore
import Testing
import Tracks

@testable import FeatureStoreBuilder
@testable import TrackMatching

/// The legs along ways that a matched stretch gives.
@Suite("Track legs")
struct TrackLegsTests {
    /// 60 N, 10 E; a step of 0.0001 degrees of longitude is 5.6 m there.
    private func packed(_ east: Double, _ north: Double) -> PackedPoint {
        PackedPoint(longitude: 100_000_000 + Int32((east * 1_000).rounded()), latitude: 600_000_000 + Int32((north * 1_000).rounded()))
    }

    private func way(_ id: Int64, _ points: [(Double, Double)], offset: UInt32 = 0) -> StoredFeature {
        StoredFeature(
            classID: FeatureClass.path.rawValue, kind: .line, objectType: .way, objectID: id, offsetAlongLine: offset,
            parts: [GeometryPart(points: points.map { packed($0.0, $0.1) })])
    }

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// Fixes along a line from east `from` to east `to` (in steps of 0.0001 degrees, on the latitude `north`), a fix about every 11 m,
    /// `secondsPerFix` apart, the first at `first` seconds.
    /// Fixes along a polyline through corners (in steps of 0.0001 degrees), a fix about every 11 m, `secondsPerFix` apart.
    private func follow(_ corners: [(Double, Double)], secondsPerFix: Double = 4) -> [TrackPoint] {
        var points: [TrackPoint] = []
        for (from, to) in zip(corners, corners.dropFirst()) {
            let count = max(Int((hypot((to.0 - from.0) * 5.56, (to.1 - from.1) * 11.12) / 11).rounded()), 1)
            for index in (points.isEmpty ? 0 : 1)...count {
                let t = Double(index) / Double(count)
                points.append(
                    TrackPoint(
                        coordinate: Coordinate(latitude: 60 + (from.1 + (to.1 - from.1) * t) * 0.0001, longitude: 10 + (from.0 + (to.0 - from.0) * t) * 0.0001),
                        time: start.addingTimeInterval(Double(points.count) * secondsPerFix)))
            }
        }
        return points
    }

    private func walk(_ from: Double, _ to: Double, north: Double = 0, first: Double = 0, secondsPerFix: Double = 4) -> [TrackPoint] {
        let count = max(Int((abs(to - from) * 5.6 / 11).rounded()), 1)
        return (0...count).map { index in
            let east = from + (to - from) * Double(index) / Double(count)
            return TrackPoint(
                coordinate: Coordinate(latitude: 60 + north * 0.0001, longitude: 10 + east * 0.0001),
                time: start.addingTimeInterval(first + Double(index) * secondsPerFix))
        }
    }

    private func legs(_ points: [TrackPoint], on network: LineNetwork) throws -> [TrackLeg] {
        let matched = TrackMatcher.match(TrackSegment(points: points), on: network)
        let stretch = try #require(matched.stretches.first)
        #expect(matched.stretches.count == 1 && stretch.isMatched)
        return TrackLegs.legs(of: stretch, points: points, in: network)
    }

    @Test("An edge knows its distance along the whole way, from the offset of the piece the store keeps")
    func wayOffsets() {
        let network = LineNetwork(features: [way(1, [(0, 0), (50, 0), (100, 0)], offset: 50_000)])
        #expect(network.edges.count == 2)
        let first = network.edges.min { $0.wayOffset < $1.wayOffset }!, second = network.edges.max { $0.wayOffset < $1.wayOffset }!
        #expect(abs(first.wayOffset - 500) < 1e-9 && abs(second.wayOffset - (500 + first.length)) < 1e-6)
        let other = LineNetwork(features: [way(1, [(0, 0), (50, 0), (100, 0)])])
        #expect(other.edges.allSatisfy { $0.wayOffset < 300 } && other.edges.contains { $0.wayOffset == 0 })
    }

    @Test("A track along a way is one leg in the direction of the way, with the range and the times of the track")
    func forward() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (100, 0)])])
        let points = walk(10, 90)
        let result = try legs(points, on: network)
        let leg = try #require(result.first)
        #expect(result.count == 1 && leg.direction == .forward && leg.wayID == 1)
        #expect(abs(leg.lowerMetre - 55.6) < 2 && abs(leg.upperMetre - 500.4) < 2, "range \(leg.lowerMetre) to \(leg.upperMetre)")
        #expect(leg.start == points.first?.time && leg.end == points.last?.time)
        #expect(leg.samples.map(\.time) == leg.samples.map(\.time).sorted())
    }

    @Test("A track against the order of the nodes is a backward leg, over the same range")
    func backward() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (100, 0)])])
        let result = try legs(walk(90, 10), on: network)
        let leg = try #require(result.first)
        #expect(result.count == 1 && leg.direction == .backward)
        #expect(abs(leg.lowerMetre - 55.6) < 2 && abs(leg.upperMetre - 500.4) < 2)
    }

    @Test("The offset of the piece is part of the range")
    func offsetInRange() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (100, 0)], offset: 100_000)])
        let leg = try #require(try legs(walk(10, 90), on: network).first)
        #expect(abs(leg.lowerMetre - 1_055.6) < 2 && abs(leg.upperMetre - 1_500.4) < 2)
    }

    @Test("Out and back on a way is two legs, one each way, that meet at the turn")
    func outAndBack() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (100, 0)])])
        let out = walk(10, 70), back = walk(70, 10, first: 4 * Double(walk(10, 70).count))
        let result = try legs(out + back.dropFirst(), on: network)
        #expect(result.map(\.direction) == [.forward, .backward])
        #expect(abs(result[0].upperMetre - result[1].upperMetre) < 2 && result[0].samples.last == result[1].samples.first)
    }

    @Test("A step back of less than the turn distance is jitter and does not cut the leg")
    func jitter() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (100, 0)])])
        // 0 to 40 steps, 4 steps (22 m) back, then on to 90.
        let a = walk(10, 50), b = walk(50, 46, first: 100), c = walk(46, 90, first: 200)
        let result = try legs(a + b.dropFirst() + c.dropFirst(), on: network)
        #expect(result.count == 1 && result[0].direction == .forward)
    }

    @Test("Where the track goes from one way to the next the leg ends, and the time at the node is between the two fixes")
    func changeOfWay() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (50, 0)]), way(2, [(50, 0), (100, 0)])])
        let points = walk(10, 90)
        let result = try legs(points, on: network)
        #expect(result.map(\.wayID) == [1, 2] && result.allSatisfy { $0.direction == .forward })
        #expect(abs(result[0].upperMetre - result[0].samples.last!.metre) < 1e-9 && abs(result[0].upperMetre - 278) < 2)
        #expect(result[0].end == result[1].start && result[0].end > points[0].time! && result[1].end == points.last?.time)
        // The node is half way: the time is about half of the track time.
        let fraction = result[0].end.timeIntervalSince(points[0].time!) / points.last!.time!.timeIntervalSince(points[0].time!)
        #expect(abs(fraction - 0.5) < 0.05, "fraction \(fraction)")
    }

    @Test("A leg shorter than the minimum is noise and a raw stretch has no legs")
    func shortAndRaw() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (100, 0)])])
        let points = walk(10, 11)
        let matched = TrackMatcher.match(TrackSegment(points: points), on: network)
        #expect(matched.stretches.allSatisfy { TrackLegs.legs(of: $0, points: points, in: network).isEmpty })
        let far = walk(10, 90, north: 40)
        let rawStretch = TrackMatcher.match(TrackSegment(points: far), on: network).stretches[0]
        #expect(!rawStretch.isMatched && TrackLegs.legs(of: rawStretch, points: far, in: network).isEmpty)
    }

    @Test("A fix without a time is left out, and the time still runs from the fixes that have one")
    func missingTime() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (100, 0)])])
        var points = walk(10, 90)
        let removed = points.count / 2
        points[removed].time = nil
        let result = try legs(points, on: network)
        #expect(result.count == 1 && result[0].start == points.first?.time && result[0].end == points.last?.time)
    }

    @Test("A short stretch off the line that the matcher takes in leaves one leg, and the fixes after it keep their places")
    func absorbedWobble() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (100, 0)])])
        // 44 m (0.0004 degrees of latitude, beyond the reach) off the line for four fixes, in the middle of the way, and a raw stretch of up to 300 m is taken in.
        var points = walk(10, 90)
        let middle = points.count / 2
        for index in middle..<(middle + 4) { points[index].coordinate = Coordinate(latitude: points[index].coordinate.latitude + 0.0004, longitude: points[index].coordinate.longitude) }
        var rules = MatchingRules.standard
        rules.minimumRawLength = 300
        let matched = TrackMatcher.match(TrackSegment(points: points), on: network, rules: rules)
        let counted = matched.stretches.filter(\.isMatched)
        #expect(counted.count == 1, "the wobble is taken in: \(matched.stretches.map(\.pointRange))")
        let result = TrackLegs.legs(of: counted[0], points: points, in: network)
        #expect(result.count == 1 && result[0].direction == .forward && abs(result[0].upperMetre - 500.4) < 3)
    }

    @Test("Two ways a metre or two apart, joined by a hop: each is travelled in the direction of the track, with no extra legs")
    func hop() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (50, 0)]), way(2, [(50.3, 0), (100, 0)])])
        let points = walk(10, 90)
        let matched = TrackMatcher.match(TrackSegment(points: points), on: network)
        let result = matched.stretches.flatMap { TrackLegs.legs(of: $0, points: points, in: network) }
        #expect(result.map(\.wayID) == [1, 2] && result.allSatisfy { $0.direction == .forward }, "\(result.map { ($0.wayID, $0.lowerMetre, $0.upperMetre) })")
        #expect(result[0].upperMetre < 290 && result[1].lowerMetre < 5 && result[1].upperMetre < 230)
    }

    @Test("Where the edges are not connected the leg ends, and no time is shared across the gap")
    func gap() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (50, 0)]), way(2, [(68, 0), (118, 0)])])
        let points = walk(10, 108)
        var rules = MatchingRules.standard
        rules.minimumRawLength = 400
        let matched = TrackMatcher.match(TrackSegment(points: points), on: network, rules: rules)
        let stretch = try #require(matched.stretches.first)
        #expect(matched.stretches.count == 1 && stretch.isMatched && !stretch.edgeGaps.isEmpty, "stretches \(matched.stretches.map(\.pointRange))")
        let result = TrackLegs.legs(of: stretch, points: points, in: network)
        #expect(result.map(\.wayID) == [1, 2])
        #expect(result[0].end < result[1].start, "the legs do not meet: the track was on neither way in between")
    }

    @Test("A closed way that the track passes the start of is two legs, one to the end of the way and one from its start")
    func closedWay() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (40, 0), (40, 10), (0, 10), (0, 0)])])
        let result = try legs(follow([(20, 0), (40, 0), (40, 10), (0, 10), (0, 0), (20, 0)]), on: network)
        #expect(result.count == 2 && result.allSatisfy { $0.wayID == 1 && $0.direction == .forward })
        #expect(result[0].lowerMetre > 100 && result[1].lowerMetre < 1 && result[1].upperMetre > 100)
        #expect(abs(result[0].upperMetre - (network.edges.map(\.length).reduce(0, +))) < 1, "the first leg ends at the end of the way")
    }

    @Test("A leg that ends with a small step back keeps the direction of the leg")
    func wobbleAtTheEnd() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (100, 0)])])
        let result = try legs(walk(10, 40) + walk(40, 36, first: 200).dropFirst(), on: network)
        #expect(result.count == 1 && result[0].direction == .forward)
    }

    @Test("The turn distance and the minimum length are the caller's: a longer turn distance keeps a there-and-back as one leg, a longer minimum drops the leg")
    func parameters() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (100, 0)])])
        let points = walk(10, 70) + walk(70, 10, first: 200).dropFirst()
        let stretch = try #require(TrackMatcher.match(TrackSegment(points: points), on: network).stretches.first)
        #expect(TrackLegs.legs(of: stretch, points: points, in: network).count == 2)
        #expect(TrackLegs.legs(of: stretch, points: points, in: network, turnDistance: 500).count == 1)
        #expect(TrackLegs.legs(of: stretch, points: points, in: network, minimumLength: 400).isEmpty)
        // A turn of exactly the turn distance counts as a turn, one a little less does not.
        let out = walk(10, 50), back = walk(50, 40, first: 100)
        let small = TrackLegs.legs(of: try #require(TrackMatcher.match(TrackSegment(points: out + back.dropFirst()), on: network).stretches.first), points: out + back.dropFirst(), in: network, turnDistance: 100)
        #expect(small.count == 1)
    }

    @Test("A time that goes back is set to the one before it: no leg ends before it starts")
    func timesGoingBack() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (100, 0)])])
        var points = walk(10, 90)
        points[points.count / 2].time = start.addingTimeInterval(-1_000)
        let result = try legs(points, on: network)
        #expect(result.allSatisfy { $0.elapsed >= 0 && $0.samples.map(\.time) == $0.samples.map(\.time).sorted() })
    }

    @Test("The legs of a matched track are those of its counted stretches, and a cleaned track of another size is refused")
    func wholeTrack() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (100, 0)])])
        let points = walk(10, 90)
        let cleaned = CleanedTrack(segments: [TrackSegment(points: points)], breaks: [], mergedPoints: 0, droppedSegments: 0)
        let matched = TrackMatcher.match(cleaned, on: network)
        let result = try TrackLegs.legs(of: matched, from: cleaned, in: network)
        #expect(result.count == 1 && result[0].direction == .forward)
        #expect(try TrackLegs.legs(of: matched, from: cleaned, in: network, minimumStretchLength: 10_000).isEmpty)
        #expect(throws: TrackLegsError.segmentCountsDiffer(matched: 0, cleaned: 1)) {
            try TrackLegs.legs(of: MatchedTrack(segments: []), from: cleaned, in: network)
        }
    }

    @Test("Every fix of a stretch points at the edge it lies on, also after a short raw stretch was taken in")
    func fixes() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (30, 0), (100, 0)])])
        var points = walk(10, 90)
        let middle = points.count / 2
        for index in middle..<(middle + 4) {
            points[index].coordinate = Coordinate(latitude: points[index].coordinate.latitude + 0.0004, longitude: points[index].coordinate.longitude)
        }
        var rules = MatchingRules.standard
        rules.minimumRawLength = 300
        let stretch = try #require(TrackMatcher.match(TrackSegment(points: points), on: network, rules: rules).stretches.first)
        #expect(stretch.fixes.count > 10 && stretch.fixes.map(\.point) == stretch.fixes.map(\.point).sorted())
        for fix in stretch.fixes {
            #expect(fix.edgeIndex >= 0 && fix.edgeIndex < stretch.edges.count)
            let edge = stretch.edges[fix.edgeIndex]
            #expect(network.edges(near: points[fix.point].coordinate, within: 40).contains { $0.edge == edge }, "fix at point \(fix.point)")
        }
    }

    @Test("The offset along the way agrees with the offsets that the store builder gives the pieces of a line cut at cell borders")
    func offsetsAgreeWithTheBuilder() {
        let line = (0...12).map { PackedPoint(longitude: 100_000_000 + Int32($0) * 1_000_000, latitude: 600_000_000) }
        let pieces = CellSplitter.split(line: line)
        #expect(pieces.count >= 3, "the line crosses cell borders")
        let features = pieces.map {
            StoredFeature(
                classID: FeatureClass.path.rawValue, kind: .line, objectType: .way, objectID: 1, offsetAlongLine: $0.piece.offsetCentimetres,
                parts: [GeometryPart(points: $0.piece.points)])
        }
        let network = LineNetwork(features: features)
        // The distance along the original line: the steps between its vertices, then the way to the place from the vertex before it.
        let vertices = line.map { Coordinate(latitude: Double($0.latitude) / 1e7, longitude: Double($0.longitude) / 1e7) }
        var cumulative = [0.0]
        for (a, b) in zip(vertices, vertices.dropFirst()) { cumulative.append(cumulative[cumulative.count - 1] + a.distance(to: b)) }
        for edge in network.edges {
            let place = network.coordinates[edge.from]
            let index = min(Int(((place.longitude - 10) / 0.1).rounded(.down)), vertices.count - 1)
            let expected = cumulative[index] + vertices[index].distance(to: place)
            #expect(abs(edge.wayOffset - expected) < 0.2, "offset \(edge.wayOffset), expected \(expected)")
        }
    }
}
