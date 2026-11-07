import FeatureStore

/// Joins ways end to end, by shared node ID, into closed rings and open chains.
///
/// Ways are processed in ID order, and where several unused ways meet at one node the
/// lowest ID is taken, so the result does not depend on the order of the input. A
/// closed way is a ring by itself. Only the forward direction is extended, which is
/// enough for rings; an open chain may therefore be reported in two parts.
enum RingJoiner {
    struct Way {
        let id: Int64
        let nodeIDs: [Int64]
        let points: [PackedPoint]
    }

    struct Result {
        /// Closed rings (the first point is repeated at the end), with at least four points.
        var rings: [[PackedPoint]] = []
        /// Chains that did not close.
        var chains: [[PackedPoint]] = []
        /// Ways dropped because they had fewer than two distinct nodes, or were closed with fewer than four points.
        var degenerate = 0
    }

    static func join(_ input: [Way]) -> Result {
        var result = Result()
        var ways: [Way] = []
        for way in input.sorted(by: { $0.id < $1.id }) {
            let cleaned = removingRepeats(way)
            if cleaned.nodeIDs.count < 2 { result.degenerate += 1 } else { ways.append(cleaned) }
        }

        // Closed ways are rings.
        var open: [Way] = []
        for way in ways {
            if way.nodeIDs.first == way.nodeIDs.last {
                if way.nodeIDs.count >= 4 { result.rings.append(way.points) } else { result.degenerate += 1 }
            } else {
                open.append(way)
            }
        }

        var endpoints: [Int64: [Int]] = [:]
        for (index, way) in open.enumerated() {
            endpoints[way.nodeIDs[0], default: []].append(index)
            endpoints[way.nodeIDs[way.nodeIDs.count - 1], default: []].append(index)
        }
        var used = [Bool](repeating: false, count: open.count)
        for start in open.indices where !used[start] {
            used[start] = true
            var nodes = open[start].nodeIDs
            var points = open[start].points
            var closed = false
            while true {
                guard let tail = nodes.last else { break }
                if tail == nodes[0], nodes.count >= 4 { closed = true; break }
                // The lowest-ID unused way that has the tail as an end point; `endpoints` lists are in index (ID) order.
                guard let next = endpoints[tail]?.first(where: { !used[$0] }) else { break }
                used[next] = true
                let way = open[next]
                if way.nodeIDs[0] == tail {
                    nodes.append(contentsOf: way.nodeIDs.dropFirst())
                    points.append(contentsOf: way.points.dropFirst())
                } else {
                    nodes.append(contentsOf: way.nodeIDs.reversed().dropFirst())
                    points.append(contentsOf: way.points.reversed().dropFirst())
                }
            }
            if closed { result.rings.append(points) } else { result.chains.append(points) }
        }
        return result
    }

    private static func removingRepeats(_ way: Way) -> Way {
        var nodeIDs: [Int64] = []
        var points: [PackedPoint] = []
        for (id, point) in zip(way.nodeIDs, way.points) where id != nodeIDs.last {
            nodeIDs.append(id)
            points.append(point)
        }
        return Way(id: way.id, nodeIDs: nodeIDs, points: points)
    }
}
