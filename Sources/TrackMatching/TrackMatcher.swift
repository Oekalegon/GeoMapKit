import Foundation
import GeoCore
import Tracks

/// Lays a cleaned track on the lines of a map where it follows them, and leaves it as recorded where it does not.
///
/// The method is the hidden Markov model of Newson and Krumm. Each fix has the lines within reach as candidates, scored by how near they
/// are; between two fixes, a candidate is scored by how well the route along the network agrees with the straight step. A further state,
/// "on no line", is always there, so a track that crosses open ground, a frozen lake or a beach is left raw and does not drag a road
/// across it, and a fix that has no line in reach does not stop the match. The best sequence of states is found with the Viterbi
/// algorithm.
///
/// The matcher uses only the network and the points. It runs on the phone or the Mac, not on the Watch: the network holds every vertex of
/// the area in memory.
///
/// A track that changes from one way to another where they share no vertex (a bridge over a road) has a raw stretch of a fix or two there;
/// one wobble can do the same. A raw stretch shorter than ``MatchingRules/minimumRawLength`` between two matched ones is taken into them,
/// and ``MatchedStretch/edgeGaps`` says where the edges of such a stretch are not connected.
public enum TrackMatcher {
    /// Matches every segment of a cleaned track.
    ///
    /// - Parameters:
    ///   - cleaned: The track, from ``TrackCleaner``.
    ///   - network: The lines of the map around the track.
    ///   - rules: How to match; the rules of a sport.
    public static func match(_ cleaned: CleanedTrack, on network: LineNetwork, rules: MatchingRules = .standard) -> MatchedTrack {
        MatchedTrack(segments: cleaned.segments.map { match($0, on: network, rules: rules) })
    }

    /// Matches one unbroken segment.
    ///
    /// - Parameters:
    ///   - segment: The segment.
    ///   - network: The lines of the map around the segment.
    ///   - rules: How to match.
    /// - Returns: Matched and raw stretches that follow each other and cover every point of the segment.
    public static func match(_ segment: TrackSegment, on network: LineNetwork, rules: MatchingRules = .standard) -> MatchedSegment {
        let points = segment.points.map(\.coordinate)
        let steps = stepLengths(of: points)
        guard points.count >= 2, !network.edges.isEmpty else { return MatchedSegment(stretches: [raw(points, 0..<points.count, steps)]) }

        // The fixes that are used: not closer than the minimum spacing to the last one used; the last fix always.
        var used = [0]
        for index in 1..<points.count where points[index].distance(to: points[used[used.count - 1]]) >= rules.minimumSpacing {
            used.append(index)
        }
        if used[used.count - 1] != points.count - 1 { used.append(points.count - 1) }

        let candidates: [[EdgeProjection]] = used.map { candidateLines(near: points[$0], in: network, rules: rules) }
        guard candidates.contains(where: { !$0.isEmpty }) else { return MatchedSegment(stretches: [raw(points, 0..<points.count, steps)]) }

        var router = NetworkRouter(network: network, hopDistance: rules.hopDistance)
        let states = bestStates(points: points, used: used, candidates: candidates, router: &router, rules: rules)
        return MatchedSegment(
            stretches: stretches(
                points: points, steps: steps, used: used, candidates: candidates, states: states, router: &router, rules: rules, network: network))
    }

    // MARK: Candidates

    /// The lines that a fix may be on: the nearest edge of each way first, so that a way of many short edges does not use all the places
    /// and hide a parallel road or path, then the other nearest edges, up to the most the rules allow.
    ///
    /// - Parameters:
    ///   - coordinate: The fix.
    ///   - network: The lines.
    ///   - rules: The reach, the classes and the number of candidates.
    /// - Returns: The candidates, nearest first.
    static func candidateLines(near coordinate: Coordinate, in network: LineNetwork, rules: MatchingRules) -> [EdgeProjection] {
        let near = network.edges(near: coordinate, within: rules.reach).filter { rules.classes.contains(network.edges[$0.edge].classID) }
        var chosen: [EdgeProjection] = []
        var ways = Set<Int64>()
        for projection in near where chosen.count < rules.maximumCandidates && ways.insert(network.edges[projection.edge].wayID).inserted {
            chosen.append(projection)
        }
        for projection in near where chosen.count < rules.maximumCandidates && !chosen.contains(where: { $0.edge == projection.edge }) {
            chosen.append(projection)
        }
        return chosen.sorted { $0.distance < $1.distance }
    }

    // MARK: Viterbi

    /// For each used fix, the index of its candidate in `candidates`, or the count of the candidates for "on no line".
    private static func bestStates(
        points: [Coordinate], used: [Int], candidates: [[EdgeProjection]], router: inout NetworkRouter, rules: MatchingRules
    ) -> [Int] {
        let variance = 2 * rules.gpsSigma * rules.gpsSigma
        let offEmission = -(rules.offNetworkDistance * rules.offNetworkDistance) / variance
        func emission(_ candidate: EdgeProjection) -> Double { -(candidate.distance * candidate.distance) / variance }

        var delta = candidates[0].map(emission) + [offEmission]
        var back: [[Int]] = [[]]
        for step in 1..<used.count {
            let previous = candidates[step - 1], current = candidates[step]
            let straight = points[used[step - 1]].distance(to: points[used[step]])
            let limit = straight * rules.maximumDetour + rules.detourSlack
            let searches = current.isEmpty ? [] : previous.map { router.search(from: $0, limit: limit) }
            var next = [Double](repeating: -.infinity, count: current.count + 1)
            var source = [Int](repeating: previous.count, count: current.count + 1)
            for (index, candidate) in current.enumerated() {
                // From "on no line": a switch back to the lines.
                var best = delta[previous.count] - rules.switchPenalty
                var from = previous.count
                for (before, start) in previous.enumerated() where delta[before] > -.infinity {
                    guard let route = router.distance(in: searches[before], from: start, to: candidate) else { continue }
                    let score = delta[before] - abs(route - straight) / rules.transitionBeta
                    if score > best { best = score; from = before }
                }
                next[index] = best + emission(candidate)
                source[index] = from
            }
            var best = delta[previous.count]
            var from = previous.count
            for before in previous.indices where delta[before] - rules.switchPenalty > best {
                best = delta[before] - rules.switchPenalty
                from = before
            }
            next[current.count] = best + offEmission
            source[current.count] = from
            delta = next
            back.append(source)
        }
        var state = delta.indices.max { delta[$0] < delta[$1] } ?? 0
        var path = [state]
        for step in stride(from: used.count - 1, to: 0, by: -1) {
            state = back[step][state]
            path.append(state)
        }
        return path.reversed()
    }

    // MARK: Stretches

    private static func stretches(
        points: [Coordinate], steps: [Double], used: [Int], candidates: [[EdgeProjection]], states: [Int], router: inout NetworkRouter,
        rules: MatchingRules, network: LineNetwork
    ) -> [MatchedStretch] {
        func isMatched(_ step: Int) -> Bool { states[step] < candidates[step].count }
        var result: [MatchedStretch] = []
        var first = 0
        while first < used.count {
            var last = first
            while last + 1 < used.count, isMatched(last + 1) == isMatched(first) { last += 1 }
            let lower = result.isEmpty ? 0 : used[first]
            let upper = last + 1 < used.count ? used[last + 1] : points.count
            if isMatched(first) {
                result.append(
                    matchedStretch(
                        points: points, steps: steps, used: used, candidates: candidates, states: states, group: first...last,
                        range: lower..<upper, router: &router, rules: rules, network: network))
            } else {
                result.append(raw(points, lower..<upper, steps))
            }
            first = last + 1
        }
        return joined(absorbingShortRaw(result, rules: rules, network: network))
    }

    /// Takes a raw stretch that is shorter than the rules allow into the matched stretches on both sides of it.
    private static func absorbingShortRaw(_ stretches: [MatchedStretch], rules: MatchingRules, network: LineNetwork) -> [MatchedStretch] {
        func connected(_ first: Int, _ second: Int) -> Bool {
            let a = network.edges[first], b = network.edges[second]
            return a.from == b.from || a.from == b.to || a.to == b.from || a.to == b.to
        }
        var list = stretches
        var index = 1
        while index + 1 < list.count {
            let before = list[index - 1], between = list[index], after = list[index + 1]
            guard before.isMatched, !between.isMatched, after.isMatched, between.length < rules.minimumRawLength else {
                index += 1
                continue
            }
            // The short length counts for the class of the last line before it.
            var byClass = before.lengthByClass
            for (key, value) in after.lengthByClass { byClass[key, default: 0] += value }
            if let edge = before.edges.last { byClass[network.edges[edge].classID, default: 0] += between.length }
            // The edges of both, with the place where they are not connected noted.
            var edges = before.edges
            var gaps = before.edgeGaps
            var position: [Int] = []
            for (number, edge) in after.edges.enumerated() {
                if number == 0, let last = edges.last {
                    if last == edge { position.append(edges.count - 1); continue }
                    if !connected(last, edge) { gaps.append(edges.count - 1) }
                }
                edges.append(edge)
                position.append(edges.count - 1)
            }
            gaps += after.edgeGaps.map { position[$0] }
            let weight = before.length + after.length
            list.replaceSubrange(
                (index - 1)...(index + 1),
                with: [
                    MatchedStretch(
                        pointRange: before.pointRange.lowerBound..<after.pointRange.upperBound, isMatched: true,
                        confidence: weight > 0
                            ? (before.confidence * before.length + after.confidence * after.length) / weight
                            : min(before.confidence, after.confidence),
                        coordinates: before.coordinates + between.coordinates + after.coordinates, edges: edges,
                        length: before.length + between.length + after.length, lengthByClass: byClass, edgeGaps: gaps)
                ])
            // The stretch after the merged one is now at `index`, so the same place is looked at again: a chain collapses.
        }
        return list
    }

    /// Gives each stretch the first point of the next as `joinsTo`, so that the lines of the stretches meet and no gap is drawn.
    private static func joined(_ stretches: [MatchedStretch]) -> [MatchedStretch] {
        stretches.enumerated().map { index, stretch in
            guard index + 1 < stretches.count, let next = stretches[index + 1].coordinates.first else { return stretch }
            return MatchedStretch(
                pointRange: stretch.pointRange, isMatched: stretch.isMatched, confidence: stretch.confidence, coordinates: stretch.coordinates,
                edges: stretch.edges, length: stretch.length, lengthByClass: stretch.lengthByClass, edgeGaps: stretch.edgeGaps, joinsTo: next)
        }
    }

    private static func matchedStretch(
        points: [Coordinate], steps: [Double], used: [Int], candidates: [[EdgeProjection]], states: [Int], group: ClosedRange<Int>,
        range: Range<Int>, router: inout NetworkRouter, rules: MatchingRules, network: LineNetwork
    ) -> MatchedStretch {
        func candidate(_ step: Int) -> EdgeProjection { candidates[step][states[step]] }
        var coordinates = [candidate(group.lowerBound).coordinate]
        var edges = [candidate(group.lowerBound).edge]
        var routeLength = 0.0, straightLength = 0.0, mismatch = 0.0
        for step in group.dropFirst() {
            let from = candidate(step - 1), to = candidate(step)
            let straight = points[used[step - 1]].distance(to: points[used[step]])
            let limit = straight * rules.maximumDetour + rules.detourSlack
            let search = router.search(from: from, limit: limit)
            if let route = router.route(in: search, from: from, to: to) {
                coordinates += route.nodes.map { network.coordinates[$0] }
                for edge in route.edges where edges.last != edge { edges.append(edge) }
                routeLength += route.distance
                mismatch += abs(route.distance - straight)
            } else {
                // The search that chose this state found a route, so this does not happen; the fix is then joined directly.
                mismatch += straight
            }
            straightLength += straight
            coordinates.append(to.coordinate)
        }
        // Each recorded step counts for the class of the line the nearest used fix at or before it lies on.
        var lengthByClass: [UInt8: Double] = [:]
        var length = 0.0
        var current = group.lowerBound
        for index in range where index > 0 {
            while current + 1 <= group.upperBound, used[current + 1] <= index { current += 1 }
            let step = steps[index - 1]
            length += step
            lengthByClass[network.edges[candidate(current).edge].classID, default: 0] += step
        }
        let meanDistance = group.reduce(0.0) { $0 + candidate($1).distance } / Double(group.count)
        let proximity = rules.reach > 0 ? max(0, 1 - meanDistance / rules.reach) : 0
        let agreement = max(0, 1 - mismatch / max(straightLength, 1))
        return MatchedStretch(
            pointRange: range, isMatched: true, confidence: proximity * agreement, coordinates: coordinates, edges: edges, length: length,
            lengthByClass: lengthByClass)
    }

    /// A stretch that is left as recorded.
    private static func raw(_ points: [Coordinate], _ range: Range<Int>, _ steps: [Double]) -> MatchedStretch {
        let length = range.reduce(0.0) { $0 + ($1 > 0 ? steps[$1 - 1] : 0) }
        return MatchedStretch(
            pointRange: range, isMatched: false, confidence: 0, coordinates: Array(points[range]), edges: [], length: length, lengthByClass: [:])
    }

    /// The distance from each point to the next, in metres.
    private static func stepLengths(of points: [Coordinate]) -> [Double] {
        zip(points, points.dropFirst()).map { $0.distance(to: $1) }
    }
}
