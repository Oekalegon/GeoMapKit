import FeatureStore
import Foundation
import GeoCore
import Testing
import Tracks

@testable import TrackMatching

/// Putting off-track stretches together into traces.
@Suite("Trace builder")
struct TraceBuilderTests {
    /// A line along 60 N from east `from` to east `to`, `north` metres to the north, with a point every 10 m (1 degree of longitude is
    /// 55.6 km there).
    private func line(_ from: Double, _ to: Double, north: Double = 0, backwards: Bool = false) -> [Coordinate] {
        let count = Int(abs(to - from) / 10)
        let points = (0...count).map { index in
            Coordinate(
                latitude: 60 + north / 111_195, longitude: 10 + (from + (to - from) * Double(index) / Double(count)) / 55_597)
        }
        return backwards ? points.reversed() : points
    }

    @Test("A first stretch is a trace of its own, at the spacing of the rules, with its length and the stretch it came from")
    func firstStretch() throws {
        var builder = TraceBuilder()
        let ids = builder.add(line(0, 300), source: 7)
        let trace = try #require(builder.traces.first)
        #expect(ids == [7_000] && builder.traces.count == 1 && trace.id == 7_000 && trace.sources == [7])
        #expect(abs(trace.length - 300) < 1 && abs(Double(trace.coordinates.count) - 61) <= 1, "a vertex every 5 m: \(trace.coordinates.count)")
    }

    @Test("The same line again joins the trace, and so does the line walked back")
    func sameLine() {
        var builder = TraceBuilder()
        builder.add(line(0, 300), source: 1)
        #expect(builder.add(line(0, 300), source: 2) == [1_000])
        #expect(builder.add(line(0, 300, backwards: true), source: 3) == [1_000])
        #expect(builder.traces.count == 1 && builder.traces[0].sources == [1, 2, 3])
    }

    @Test("A line 10 m beside the trace joins it and the trace moves to the average; one 30 m beside is a trace of its own")
    func beside() throws {
        var builder = TraceBuilder()
        builder.add(line(0, 300), source: 1)
        builder.add(line(0, 300, north: 10), source: 2)
        #expect(builder.traces.count == 1)
        let middle = try #require(builder.traces[0].coordinates.dropFirst(20).first)
        #expect(abs((middle.latitude - 60) * 111_195 - 5) < 1.5, "half way between the two lines: \((middle.latitude - 60) * 111_195)")
        builder.add(line(0, 300, north: 40), source: 3)
        #expect(builder.traces.count == 2 && builder.traces[1].id == 3_000)
    }

    @Test("Running along a trace for less than the minimum join length does not join it: the whole stretch is a new trace")
    func tooShort() {
        var builder = TraceBuilder()
        builder.add(line(0, 300), source: 1)
        // 30 m along the trace, then away to the north.
        let along = line(100, 130)
        let away = (1...10).map { Coordinate(latitude: along.last!.latitude + Double($0) * 20 / 111_195, longitude: along.last!.longitude) }
        builder.add(along + away, source: 2)
        #expect(builder.traces.count == 2 && builder.traces[0].sources == [1])
    }

    @Test("A stretch that runs along a trace and then leaves it joins the trace and starts a new one for the rest")
    func partlyJoined() {
        var builder = TraceBuilder()
        builder.add(line(0, 300), source: 1)
        // 150 m along the trace, then 150 m on east beyond its end... the trace is 300 m, so run from 150 to 450.
        let ids = builder.add(line(150, 450), source: 2)
        #expect(Set(ids) == [1_000, 2_000], "\(ids)")
        #expect(builder.traces.count == 2 && builder.traces[0].sources == [1, 2] && builder.traces[1].sources == [2])
        #expect(builder.traces[1].length > 100 && builder.traces[1].length < 180)
    }

    @Test("A stretch is compared with the traces that existed before it, so a loop does not join itself")
    func loop() {
        var builder = TraceBuilder()
        let out = line(0, 200), back = line(0, 200, north: 5, backwards: true)
        builder.add(out + back, source: 1)
        #expect(builder.traces.count == 1 && builder.traces[0].sources == [1])
    }

    @Test("Stretches that are too short or have one point make no trace, and the rules are raised to what works")
    func edges() {
        var builder = TraceBuilder()
        #expect(builder.add([], source: 1).isEmpty && builder.add([Coordinate(latitude: 60, longitude: 10)], source: 1).isEmpty)
        #expect(builder.traces.isEmpty)
        let rules = TraceRules(joinDistance: 0, minimumJoinLength: -5, spacing: .nan)
        #expect(rules.joinDistance == 1 && rules.minimumJoinLength == 0 && rules.spacing == 1)
    }

    @Test("The order of the stretches matters, and the same order gives the same traces")
    func repeatable() {
        func build() -> [TrackTrace] {
            var builder = TraceBuilder()
            builder.add(line(0, 300), source: 1)
            builder.add(line(0, 300, north: 8), source: 2)
            builder.add(line(100, 400, north: 20), source: 3)
            return builder.traces
        }
        #expect(build() == build())
    }
}

/// The off-track stretches of a matched segment.
@Suite("Off-track lines")
struct OffTrackLinesTests {
    private func packed(_ east: Double, _ north: Double) -> PackedPoint {
        PackedPoint(longitude: 100_000_000 + Int32((east * 1_000).rounded()), latitude: 600_000_000 + Int32((north * 1_000).rounded()))
    }

    private func points(_ corners: [(Double, Double)]) -> [TrackPoint] {
        var result: [TrackPoint] = []
        for (from, to) in zip(corners, corners.dropFirst()) {
            let count = max(Int((hypot((to.0 - from.0) * 5.56, (to.1 - from.1) * 11.12) / 11).rounded()), 1)
            for index in (result.isEmpty ? 0 : 1)...count {
                let t = Double(index) / Double(count)
                result.append(
                    TrackPoint(
                        coordinate: Coordinate(latitude: 60 + (from.1 + (to.1 - from.1) * t) * 0.0001, longitude: 10 + (from.0 + (to.0 - from.0) * t) * 0.0001),
                        time: Date(timeIntervalSince1970: 1_700_000_000 + Double(result.count) * 4)))
            }
        }
        return result
    }

    private func way(_ id: Int64, _ list: [(Double, Double)]) -> StoredFeature {
        StoredFeature(
            classID: FeatureClass.path.rawValue, kind: .line, objectType: .way, objectID: id,
            parts: [GeometryPart(points: list.map { packed($0.0, $0.1) })])
    }

    @Test("A track that leaves the paths across open ground gives one off-track line, from the path to the path, with its time")
    func acrossOpenGround() throws {
        // Two paths 400 m apart joined only by open ground: the track runs along the first, across the field, and along the second.
        let network = LineNetwork(features: [way(1, [(0, 0), (50, 0)]), way(2, [(50, 60), (100, 60)])])
        let track = points([(10, 0), (50, 0), (50, 60), (90, 60)])
        let matched = TrackMatcher.match(TrackSegment(points: track), on: network)
        let lines = OffTrackLines.lines(of: matched, points: track)
        #expect(lines.count >= 1, "stretches \(matched.stretches.map { ($0.isMatched, $0.length) })")
        let line = try #require(lines.first)
        #expect(line.length >= 30 && line.elapsed > 0 && line.coordinates.count >= 3)
        #expect(OffTrackLines.lines(of: matched, points: track, minimumLength: 10_000).isEmpty)
    }

    @Test("A track entirely on a path has no off-track line, and a matched track of another size is refused")
    func none() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (100, 0)])])
        let track = points([(10, 0), (90, 0)])
        let cleaned = CleanedTrack(segments: [TrackSegment(points: track)], breaks: [], mergedPoints: 0, droppedSegments: 0)
        let matched = TrackMatcher.match(cleaned, on: network)
        #expect(try OffTrackLines.lines(of: matched, from: cleaned).isEmpty)
        #expect(throws: TrackLegsError.segmentCountsDiffer(matched: 0, cleaned: 1)) {
            try OffTrackLines.lines(of: MatchedTrack(segments: []), from: cleaned)
        }
        #expect(OffTrackLine(coordinates: [Coordinate(latitude: 60, longitude: 10)], start: .now, elapsed: 1, length: 1) == nil)
    }
}
