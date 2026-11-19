import FeatureStore
import Foundation
import GeoCore
import Testing
import Tracks

@testable import TrackMatching

/// Laying a track on the lines of a network.
@Suite("Track matcher")
struct TrackMatcherTests {
    /// 60 N, 10 E; a step of 0.0001 degrees of longitude is 5.6 m there, one of latitude is 11.1 m.
    private func packed(_ east: Double, _ north: Double) -> PackedPoint {
        PackedPoint(longitude: 100_000_000 + Int32((east * 1_000).rounded()), latitude: 600_000_000 + Int32((north * 1_000).rounded()))
    }

    /// A line as a way, in steps of 0.0001 degrees.
    private func way(_ id: Int64, _ points: [(Double, Double)], _ classID: FeatureClass = .path) -> StoredFeature {
        StoredFeature(
            classID: classID.rawValue, kind: .line, objectType: .way, objectID: id,
            parts: [GeometryPart(points: points.map { packed($0.0, $0.1) })])
    }

    private func coordinate(_ east: Double, _ north: Double) -> Coordinate {
        Coordinate(latitude: 60 + north * 0.0001, longitude: 10 + east * 0.0001)
    }

    /// Points along a line from `from` to `to` (in steps of 0.0001 degrees) about every 11 m, with `noise` metres to the north on every
    /// second point.
    private func track(_ from: (Double, Double), _ to: (Double, Double), noise: Double = 0) -> [TrackPoint] {
        let count = max(Int((hypot((to.0 - from.0) * 5.6, (to.1 - from.1) * 11.1) / 11).rounded()), 1)
        return (0...count).map { index in
            let t = Double(index) / Double(count)
            let wobble = index % 2 == 0 ? noise : -noise
            let point = coordinate(from.0 + (to.0 - from.0) * t, from.1 + (to.1 - from.1) * t)
            return TrackPoint(coordinate: Coordinate(latitude: point.latitude + wobble / 111_195, longitude: point.longitude))
        }
    }

    private func segment(_ points: [TrackPoint]) -> TrackSegment { TrackSegment(points: points) }

    private let pathClass = FeatureClass.path.rawValue

    @Test("A track that follows a path lies on it, with a good confidence, and all its length counts for the class of the path")
    func followsAPath() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (100, 0)])])
        let points = track((2, 0), (98, 0), noise: 3)
        let result = TrackMatcher.match(segment(points), on: network)
        let stretch = try #require(result.stretches.first)
        #expect(result.stretches.count == 1 && stretch.isMatched && stretch.pointRange == 0..<points.count)
        #expect(stretch.confidence > 0.6, "confidence \(stretch.confidence)")
        let exact = TrackMatcher.match(segment(track((2, 0), (98, 0))), on: network).stretches[0]
        #expect(exact.confidence > stretch.confidence && exact.confidence > 0.9, "a track on the line is surer: \(exact.confidence)")
        #expect(stretch.coordinates.allSatisfy { abs($0.latitude - 60) < 1e-9 }, "the points are laid on the line")
        // The recorded length is a little over the 540 m of the line, because the fixes wobble to both sides of it.
        #expect(stretch.length > 530 && stretch.length < 650 && abs((stretch.lengthByClass[pathClass] ?? 0) - stretch.length) < 1e-6)
    }

    @Test("Two lines that do not join: a track between them stays on one, as a route cannot change from one to the other")
    func parallelLines() throws {
        // A road and a path 11 m apart; the track hovers in the middle, a little nearer to one and then the other.
        let network = LineNetwork(features: [way(1, [(0, 0), (100, 0)], .roadMinor), way(2, [(0, 1), (100, 1)], .path)])
        var points = track((2, 0.5), (98, 0.5))
        for index in points.indices {
            let old = points[index].coordinate
            points[index].coordinate = Coordinate(latitude: old.latitude + (index % 3 == 0 ? -2.0 : 2.0) / 111_195, longitude: old.longitude)
        }
        let result = TrackMatcher.match(segment(points), on: network)
        let matched = result.stretches.filter(\.isMatched)
        let ways = Set(matched.flatMap(\.edges).map { network.edges[$0].wayID })
        #expect(result.stretches.count == 1 && matched.count == 1 && ways.count == 1, "one stretch on one way, not both: \(ways)")
    }

    @Test("A track that leaves the lines for open ground is left raw there, and matched before and after")
    func openGround() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (40, 0)]), way(2, [(160, 0), (200, 0)])])
        let points = track((0, 0), (200, 0))
        let result = TrackMatcher.match(segment(points), on: network)
        #expect(result.stretches.map(\.isMatched) == [true, false, true])
        #expect(result.stretches.first?.pointRange.lowerBound == 0 && result.stretches.last?.pointRange.upperBound == points.count)
        let ways = result.stretches.filter(\.isMatched).map { network.edges[$0.edges[0]].wayID }
        #expect(ways == [1, 2])
        #expect(result.stretches[1].edges.isEmpty && result.stretches[1].confidence == 0)
        #expect(result.stretches[1].coordinates.count == result.stretches[1].pointRange.count + 1, "the raw line keeps its points and runs on to the next stretch")
    }

    @Test("A turn at a junction follows both ways in order, through the junction")
    func junction() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (50, 0), (100, 0)]), way(2, [(50, 0), (50, 60)])])
        let points = track((0, 0), (50, 0)) + track((50, 0), (50, 60)).dropFirst()
        let result = TrackMatcher.match(segment(Array(points)), on: network)
        let stretch = try #require(result.stretches.first)
        #expect(result.stretches.count == 1 && stretch.isMatched)
        let ways = stretch.edges.map { network.edges[$0].wayID }
        #expect(ways.first == 1 && ways.last == 2 && !ways.contains(3))
        #expect(stretch.coordinates.contains { abs($0.longitude - 10.005) < 1e-6 && abs($0.latitude - 60) < 1e-6 }, "the line passes the junction")
    }

    @Test("A gap of a metre or two between two dead ends is bridged; with no bridge the track is cut there")
    func hop() throws {
        // Two ways on one line with 1.1 m between their ends (0.0002 of a step of 5.6 m = 1.1 m).
        let network = LineNetwork(features: [way(1, [(0, 0), (50, 0)]), way(2, [(50.2, 0), (100, 0)])])
        let points = track((2, 0), (98, 0))
        let bridged = TrackMatcher.match(segment(points), on: network)
        #expect(bridged.stretches.count == 1 && bridged.stretches[0].isMatched)
        #expect(Set(bridged.stretches[0].edges.map { network.edges[$0].wayID }) == [1, 2])
        let cut = TrackMatcher.match(segment(points), on: network, rules: MatchingRules(hopDistance: 0, minimumRawLength: 0))
        #expect(bridged.stretches[0].edges == [0, 1])
        #expect(cut.stretches.map(\.isMatched) == [true, false, true], "without the bridge the track is cut at the gap, with the fix in it raw")
        #expect(cut.stretches[0].edges == [0] && cut.stretches[2].edges == [1])
    }

    @Test("Where two ways share no vertex (a bridge) the short raw stretch between them is taken into the matched ones, unless the rules keep it")
    func bridge() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (100, 0)]), way(2, [(50, -50), (50, 50)], .roadMinor)])
        let points = track((0, 0), (50, 0)) + track((50, 0), (50, 50)).dropFirst()
        let apart = TrackMatcher.match(segment(Array(points)), on: network, rules: MatchingRules(minimumRawLength: 0))
        let ways = apart.stretches.filter(\.isMatched).map { network.edges[$0.edges[0]].wayID }
        #expect(ways == [1, 2] && apart.stretches.contains { !$0.isMatched }, "the two ways are not joined, so the track is not laid across")
        let merged = TrackMatcher.match(segment(Array(points)), on: network)
        #expect(merged.stretches.count == 1 && merged.stretches[0].isMatched)
        #expect(merged.stretches[0].pointRange == 0..<points.count)
        #expect(Set(merged.stretches[0].edges.map { network.edges[$0].wayID }) == [1, 2])
        // The lengths still add up: all of it counts for a class.
        #expect(abs(merged.length - merged.stretches[0].lengthByClass.values.reduce(0, +)) < 1e-6)
    }

    @Test("The lines of the stretches meet: each runs on to the first point of the next")
    func stretchesMeet() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (40, 0)]), way(2, [(160, 0), (200, 0)])])
        let result = TrackMatcher.match(segment(track((0, 0), (200, 0))), on: network)
        #expect(result.stretches.count == 3)
        for (before, after) in zip(result.stretches, result.stretches.dropFirst()) {
            #expect(before.coordinates.last == after.coordinates.first)
        }
    }

    @Test("Only the matched stretches that are sure and long enough are counted")
    func counted() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (40, 0)]), way(2, [(160, 0), (200, 0)])])
        let result = TrackMatcher.match(CleanedTrack(segments: [segment(track((0, 0), (200, 0)))], breaks: [], mergedPoints: 0, droppedSegments: 0), on: network)
        #expect(result.countedStretches().count == 2)
        #expect(result.countedStretches(minimumLength: 1_000).isEmpty)
        #expect(result.countedStretches(minimumConfidence: 1.1).isEmpty)
        #expect(result.countedStretches(minimumConfidence: 0, minimumLength: 0).allSatisfy { $0.isMatched })
    }

    @Test("Many short edges of one way do not hide a parallel way: it is a candidate too")
    func candidatesByWay() throws {
        // A way that zigzags in 10 short edges, all within reach of the fix, and a straight way 22 m to the north.
        let zigzag = (0...10).map { (Double($0), $0 % 2 == 0 ? 0.0 : 0.02) }
        let network = LineNetwork(features: [way(1, zigzag), way(2, [(-20, 2), (30, 2)])])
        let fix = coordinate(5, 0)
        let rules = MatchingRules(maximumCandidates: 3)
        let found = TrackMatcher.candidateLines(near: fix, in: network, rules: rules)
        #expect(found.count == 3)
        #expect(Set(found.map { network.edges[$0.edge].wayID }) == [1, 2], "the straight way is a candidate")
        #expect(found.map(\.distance) == found.map(\.distance).sorted())
    }

    @Test("There is no network: the whole segment is one raw stretch with its length")
    func noNetwork() throws {
        let points = track((0, 0), (100, 0))
        let result = TrackMatcher.match(segment(points), on: LineNetwork(features: []))
        let stretch = try #require(result.stretches.first)
        #expect(result.stretches.count == 1 && !stretch.isMatched && stretch.pointRange == 0..<points.count)
        #expect(abs(stretch.length - 560) < 15 && result.matchedLength == 0)
        #expect(TrackMatcher.match(segment([]), on: LineNetwork(features: [])).stretches.first?.pointRange == 0..<0)
    }

    @Test("A class that the rules do not use is not a line")
    func classes() {
        let network = LineNetwork(features: [way(1, [(0, 0), (100, 0)])])
        let rules = MatchingRules(classes: [FeatureClass.roadMajor.rawValue])
        #expect(TrackMatcher.match(segment(track((2, 0), (98, 0))), on: network, rules: rules).stretches.map(\.isMatched) == [false])
    }

    @Test("Out and back on one path stays matched, and the stretches cover every point once")
    func outAndBack() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (100, 0)])])
        let points = track((0, 0), (100, 0)) + track((100, 0), (0, 0)).dropFirst()
        let result = TrackMatcher.match(segment(Array(points)), on: network)
        #expect(result.stretches.allSatisfy { $0.isMatched })
        var next = 0
        for stretch in result.stretches {
            #expect(stretch.pointRange.lowerBound == next)
            next = stretch.pointRange.upperBound
        }
        #expect(next == points.count)
        #expect(abs(result.length - 1_120) < 30)
    }

    @Test("A track recorded once a second is matched without using every point, and still covers them all")
    func dense() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (200, 0)])])
        let points = (0..<370).map { TrackPoint(coordinate: Coordinate(latitude: 60, longitude: 10 + Double($0) * 3 / 55_600)) }  // 3 m apart
        let result = TrackMatcher.match(segment(points), on: network)
        #expect(result.stretches.count == 1 && result.stretches[0].pointRange == 0..<370 && result.stretches[0].isMatched)
        #expect(result.stretches[0].coordinates.count < 200, "about one point in three is used")
    }

    @Test("A cleaned track is matched segment by segment, with the terrain figures of the whole")
    func cleaned() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (100, 0)]), way(2, [(0, 30), (100, 30)], .roadMajor)])
        let cleaned = CleanedTrack(
            segments: [segment(track((2, 0), (98, 0))), segment(track((2, 30), (60, 30))), segment(track((0, 80), (60, 80)))], breaks: [], mergedPoints: 0,
            droppedSegments: 0)
        let result = TrackMatcher.match(cleaned, on: network)
        #expect(result.segments.count == 3)
        let byClass = result.lengthByClass
        #expect((byClass[pathClass] ?? 0) > 500 && (byClass[FeatureClass.roadMajor.rawValue] ?? 0) > 300)
        #expect(result.unmatchedLength > 300, "the third segment is far from every line")
        #expect(abs(result.length - (result.lengthByClass.values.reduce(0, +) + result.unmatchedLength)) < 1)
    }

    @Test("A segment of one point is one raw stretch with no length")
    func onePoint() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (100, 0)])])
        let result = TrackMatcher.match(segment([TrackPoint(coordinate: coordinate(5, 0))]), on: network)
        let stretch = try #require(result.stretches.first)
        #expect(result.stretches.count == 1 && !stretch.isMatched && stretch.pointRange == 0..<1 && stretch.length == 0)
        let nan = TrackMatcher.match(segment([TrackPoint(latitude: .nan, longitude: 10), TrackPoint(latitude: 60, longitude: 10.001)]), on: network)
        #expect(nan.stretches.map(\.isMatched) == [false, true], "a fix that is not a number has no candidates and stays raw")
    }

    @Test("The rules are kept in range")
    func rules() {
        let nan = MatchingRules(reach: .nan, gpsSigma: .nan, transitionBeta: .nan, switchPenalty: .nan)
        #expect(nan.reach == 0 && nan.gpsSigma == 1 && nan.transitionBeta == 1 && nan.switchPenalty == 0)
        let rules = MatchingRules(reach: -5, gpsSigma: 0, transitionBeta: 0, maximumDetour: 0, detourSlack: -1, maximumCandidates: 0, minimumSpacing: -1)
        #expect(rules.reach == 0 && rules.gpsSigma == 1 && rules.transitionBeta == 1 && rules.maximumDetour == 1)
        #expect(rules.detourSlack == 0 && rules.maximumCandidates == 1 && rules.minimumSpacing == 0)
        #expect(MatchingRules(minimumRawLength: -3).minimumRawLength == 0 && MatchingRules(minimumRawLength: .nan).minimumRawLength == 0)
    }
}
