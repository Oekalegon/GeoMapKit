import Foundation
import Tracks

/// Turns a matched stretch into the legs along ways that the segment statistics count.
public enum TrackLegs {
    /// The most that a way may be left again and walked back before it counts as a turn, in metres: a reversal of less than this is GPS
    /// jitter or a step back, and the leg goes on. A first value like the other thresholds.
    public static let defaultTurnDistance = 30.0
    /// The shortest range of a leg, in metres: a shorter one is noise. A first value.
    public static let defaultMinimumLength = 10.0

    /// One stretch of the movement along one edge, with the times at both ends.
    private struct Move {
        var edge: Int
        var from: Double
        var to: Double
        var start: Date
        var end: Date
    }

    /// The legs of one matched stretch.
    ///
    /// The movement between two fixes goes along the edges between them, and the time of a node on the way is interpolated by distance.
    /// A leg ends where the track changes way, where the edges are not connected (``MatchedStretch/edgeGaps``), where a closed way
    /// passes its start, and where it turns round (it goes back more than `turnDistance`, so a there-and-back is two legs).
    ///
    /// - Parameters:
    ///   - stretch: The stretch. A raw stretch has no legs.
    ///   - points: The points of the segment that the stretch is from (``MatchedStretch/pointRange`` and the fixes are indexes into it).
    ///     A fix whose point has no time is left out.
    ///   - network: The network that the matcher used. The edges of the stretch are indexes into it.
    ///   - turnDistance: How far back is a turn, in metres.
    ///   - minimumLength: The shortest range of a leg, in metres.
    /// - Returns: The legs in the order of travel.
    public static func legs(
        of stretch: MatchedStretch, points: [TrackPoint], in network: LineNetwork, turnDistance: Double = defaultTurnDistance,
        minimumLength: Double = defaultMinimumLength
    ) -> [TrackLeg] {
        guard stretch.isMatched else { return [] }
        let timed = stretch.fixes.filter { $0.point < points.count && points[$0.point].time != nil }
        guard !timed.isEmpty else { return [] }
        var legs: [TrackLeg] = []
        var run: [(edge: Int, metre: Double, time: Date)] = []
        func finish() {
            legs += cut(run, network: network, confidence: stretch.confidence, turnDistance: turnDistance, minimumLength: minimumLength)
            run = []
        }
        func add(_ move: Move) {
            let edge = network.edges[move.edge]
            let a = edge.wayOffset + move.from * edge.length, b = edge.wayOffset + move.to * edge.length
            // A different way, or a jump along the same one (a closed way passing its start), starts a new run.
            if let last = run.last, network.edges[last.edge].wayID != edge.wayID || abs(last.metre - a) > 1 { finish() }
            if run.isEmpty { run.append((move.edge, a, move.start)) }
            run.append((move.edge, b, move.end))
        }
        for (first, second) in zip(timed, timed.dropFirst()) {
            guard let start = points[first.point].time, let end = points[second.point].time else { continue }
            // No route goes across a gap: the run ends at the first fix, and the next one starts at the second.
            if stretch.edgeGaps.contains(where: { $0 >= first.edgeIndex && $0 < second.edgeIndex }) {
                finish()
                continue
            }
            let moves = route(from: first, to: second, stretch: stretch, network: network)
            let total = moves.reduce(0.0) { $0 + abs($1.to - $1.from) * network.edges[$1.edge].length }
            var done = 0.0
            for var move in moves {
                let length = abs(move.to - move.from) * network.edges[move.edge].length
                let seconds = end.timeIntervalSince(start)
                move.start = start.addingTimeInterval(total > 0 ? seconds * done / total : 0)
                done += length
                move.end = start.addingTimeInterval(total > 0 ? seconds * done / total : seconds)
                add(move)
            }
        }
        finish()
        return legs
    }

    /// The legs of all counted stretches of a matched track: the stretches that `MatchedTrack.countedStretches` would give.
    ///
    /// - Parameters:
    ///   - matched: The matched track.
    ///   - cleaned: The cleaned track it was made from (its segments are the ones the matched segments follow).
    ///   - network: The network that the matcher used.
    ///   - minimumConfidence: The least confidence of a stretch.
    ///   - minimumStretchLength: The least recorded length of a stretch, in metres.
    public static func legs(
        of matched: MatchedTrack, from cleaned: CleanedTrack, in network: LineNetwork, minimumConfidence: Double = 0.5,
        minimumStretchLength: Double = 100
    ) -> [TrackLeg] {
        zip(matched.segments, cleaned.segments).flatMap { matchedSegment, segment in
            matchedSegment.stretches
                .filter { $0.isMatched && $0.confidence >= minimumConfidence && $0.length >= minimumStretchLength }
                .flatMap { legs(of: $0, points: segment.points, in: network) }
        }
    }

    /// The movement from one fix to the next along the edges between them.
    private static func route(from first: MatchedFix, to second: MatchedFix, stretch: MatchedStretch, network: LineNetwork) -> [Move] {
        let edges = Array(stretch.edges[first.edgeIndex...second.edgeIndex])
        let zero = Date(timeIntervalSince1970: 0)
        if edges.count == 1 { return [Move(edge: edges[0], from: first.fraction, to: second.fraction, start: zero, end: zero)] }
        // The node by which the movement leaves each edge: the end that the next edge shares.
        var moves: [Move] = []
        var entry: Int?
        for (number, edge) in edges.enumerated() {
            let line = network.edges[edge]
            let exit: Int
            if number + 1 < edges.count {
                let next = network.edges[edges[number + 1]]
                exit = (line.to == next.from || line.to == next.to) ? line.to : line.from
            } else {
                exit = entry == line.from ? line.to : line.from
            }
            let forward = exit == line.to
            let start = number == 0 ? first.fraction : (forward ? 0.0 : 1.0)
            let end = number + 1 == edges.count ? second.fraction : (forward ? 1.0 : 0.0)
            moves.append(Move(edge: edge, from: start, to: end, start: zero, end: zero))
            entry = exit
        }
        return moves
    }

    /// Cuts a run along one way into legs where it turns round.
    private static func cut(
        _ run: [(edge: Int, metre: Double, time: Date)], network: LineNetwork, confidence: Double, turnDistance: Double, minimumLength: Double
    ) -> [TrackLeg] {
        guard run.count >= 2 else { return [] }
        let way = network.edges[run[0].edge]
        var legs: [TrackLeg] = []
        func emit(_ samples: ArraySlice<(edge: Int, metre: Double, time: Date)>) {
            let metres = samples.map(\.metre)
            guard let low = metres.min(), let high = metres.max(), high - low >= minimumLength, let first = samples.first, let last = samples.last
            else { return }
            legs.append(
                TrackLeg(
                    wayID: way.wayID, classID: way.classID, lowerMetre: low, upperMetre: high,
                    direction: last.metre >= first.metre ? .forward : .backward,
                    samples: samples.map { TrackLeg.Sample(metre: $0.metre, time: $0.time) }, confidence: confidence))
        }
        var legStart = 0
        var direction = 0.0  // 1 or -1 once the leg has gone `turnDistance` one way, else 0
        var extreme = 0  // the index of the furthest sample in the direction
        for index in 1..<run.count {
            let metre = run[index].metre
            if direction == 0 {
                if abs(metre - run[legStart].metre) >= turnDistance { direction = metre > run[legStart].metre ? 1 : -1; extreme = index }
            } else if (metre - run[extreme].metre) * direction >= 0 {
                extreme = index
            } else if (run[extreme].metre - metre) * direction >= turnDistance {
                emit(run[legStart...extreme])
                legStart = extreme
                direction = -direction
                extreme = index
            }
        }
        emit(run[legStart...])
        return legs
    }
}
