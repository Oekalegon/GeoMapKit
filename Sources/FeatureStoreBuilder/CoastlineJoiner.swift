import FeatureStore

/// Joins coastline ways end to end, keeping their direction.
///
/// OSM coastlines have land on the left and water on the right, so unlike ``RingJoiner`` a way is never
/// reversed: a way continues only into a way that starts at the node where it ends. Where several unused ways start at
/// one node, the lowest ID is taken, so the result does not depend on the input order.
enum CoastlineJoiner {
    struct Way {
        let id: Int64
        let nodeIDs: [Int64]
        let points: [PackedPoint]
    }

    struct Result {
        /// Closed coastlines (the first point is repeated at the end): islands (land inside) and the rare lake-like sea.
        var rings: [[PackedPoint]] = []
        /// Coastlines that do not close within the input: they leave the extract.
        var chains: [[PackedPoint]] = []
    }

    static func join(_ input: [Way]) -> Result {
        var ways: [Way] = []
        for way in input.sorted(by: { $0.id < $1.id }) {
            var nodeIDs: [Int64] = [], points: [PackedPoint] = []
            for (id, point) in zip(way.nodeIDs, way.points) where id != nodeIDs.last {
                nodeIDs.append(id)
                points.append(point)
            }
            if nodeIDs.count >= 2 { ways.append(Way(id: way.id, nodeIDs: nodeIDs, points: points)) }
        }
        var startsAt: [Int64: [Int]] = [:]
        var endNodes = Set<Int64>()
        for (index, way) in ways.enumerated() {
            startsAt[way.nodeIDs[0], default: []].append(index)
            if let last = way.nodeIDs.last { endNodes.insert(last) }
        }
        var used = [Bool](repeating: false, count: ways.count)
        var result = Result()

        func follow(from first: Int) {
            used[first] = true
            var nodes = ways[first].nodeIDs, points = ways[first].points
            while let tail = nodes.last, !(tail == nodes[0] && nodes.count >= 4) {
                guard let next = startsAt[tail]?.first(where: { !used[$0] }) else { break }
                used[next] = true
                nodes.append(contentsOf: ways[next].nodeIDs.dropFirst())
                points.append(contentsOf: ways[next].points.dropFirst())
            }
            if nodes.count >= 4, nodes.first == nodes.last { result.rings.append(points) } else { result.chains.append(points) }
        }

        // Chains first, from ways that no other way leads into; what is left over are rings.
        for index in ways.indices where !used[index] && !endNodes.contains(ways[index].nodeIDs[0]) { follow(from: index) }
        for index in ways.indices where !used[index] { follow(from: index) }
        return result
    }
}
