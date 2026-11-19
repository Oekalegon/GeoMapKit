import GeoCore

/// Shortest routes along a ``LineNetwork`` between two positions on its edges, for the matcher.
///
/// A position is a point on an edge (an ``EdgeProjection``). A route leaves it by either end of the edge, follows the edges, and reaches
/// the other position by either end of its edge. Dead ends that lie within the hop distance of each other are joined, so a way that is cut
/// at a cell border and does not join exactly can still be followed. Searches are limited in distance and so stay small.
struct NetworkRouter {
    /// The result of a search from one position: the distance to each node reached, and how it was reached.
    struct Search {
        var distance: [Int: Double] = [:]
        /// The node before and the edge used to come to a node; the edge is -1 for a hop between two dead ends.
        var previous: [Int: (node: Int, edge: Int)] = [:]
    }

    /// A route between two positions.
    struct Route {
        var distance: Double
        /// The edges followed, in order, from the edge of the first position to the edge of the second.
        var edges: [Int]
        /// The nodes passed, in order.
        var nodes: [Int]
    }

    let network: LineNetwork
    let hopDistance: Double
    private var hops: [Int: [(node: Int, metres: Double)]] = [:]

    init(network: LineNetwork, hopDistance: Double) {
        self.network = network
        self.hopDistance = hopDistance
    }

    /// The dead ends that lie within the hop distance of a dead end.
    private mutating func hopTargets(of node: Int) -> [(node: Int, metres: Double)] {
        guard hopDistance > 0, network.incident[node].count == 1 else { return [] }
        if let known = hops[node] { return known }
        var found: [(node: Int, metres: Double)] = []
        let here = network.coordinates[node]
        for projection in network.edges(near: here, within: hopDistance) {
            let edge = network.edges[projection.edge]
            for end in [edge.from, edge.to] where end != node && network.incident[end].count == 1 {
                if !found.contains(where: { $0.node == end }) { found.append((end, here.distance(to: network.coordinates[end]))) }
            }
        }
        hops[node] = found
        return found
    }

    /// Searches the network from a position, as far as `limit` metres.
    mutating func search(from start: EdgeProjection, limit: Double) -> Search {
        var search = Search()
        var queue = MinQueue()
        let edge = network.edges[start.edge]
        for (node, metres) in [(edge.from, start.fraction * edge.length), (edge.to, (1 - start.fraction) * edge.length)] where metres <= limit {
            if metres < search.distance[node, default: .infinity] {
                search.distance[node] = metres
                queue.push(metres, node)
            }
        }
        while let (metres, node) = queue.pop() {
            guard metres <= (search.distance[node] ?? .infinity) else { continue }
            var steps: [(to: Int, metres: Double, edge: Int)] = []
            for index in network.incident[node] { steps.append((network.otherEnd(of: index, from: node), network.edges[index].length, index)) }
            for hop in hopTargets(of: node) { steps.append((hop.node, hop.metres, -1)) }
            for step in steps {
                let next = metres + step.metres
                guard next <= limit, next < search.distance[step.to, default: .infinity] else { continue }
                search.distance[step.to] = next
                search.previous[step.to] = (node, step.edge)
                queue.push(next, step.to)
            }
        }
        return search
    }

    /// The distance from the start of a search to a position, or `nil` when it is beyond the limit of the search.
    func distance(in search: Search, from start: EdgeProjection, to target: EdgeProjection) -> Double? {
        if start.edge == target.edge { return abs(start.fraction - target.fraction) * network.edges[start.edge].length }
        return best(in: search, to: target)?.distance
    }

    /// The route from the start of a search to a position, or `nil` when it is beyond the limit of the search.
    func route(in search: Search, from start: EdgeProjection, to target: EdgeProjection) -> Route? {
        if start.edge == target.edge {
            return Route(distance: abs(start.fraction - target.fraction) * network.edges[start.edge].length, edges: [start.edge], nodes: [])
        }
        guard let (distance, end) = best(in: search, to: target) else { return nil }
        var nodes = [end]
        var edges: [Int] = []
        var node = end
        while let before = search.previous[node] {
            if before.edge >= 0 { edges.append(before.edge) }
            nodes.append(before.node)
            node = before.node
        }
        nodes.reverse()
        edges.reverse()
        var all = [start.edge]
        for edge in edges + [target.edge] where all.last != edge { all.append(edge) }
        return Route(distance: distance, edges: all, nodes: nodes)
    }

    /// The end of the target's edge that is nearest in the search, with the distance to the target by it.
    private func best(in search: Search, to target: EdgeProjection) -> (distance: Double, end: Int)? {
        let edge = network.edges[target.edge]
        var result: (distance: Double, end: Int)?
        if let reached = search.distance[edge.from] {
            result = (reached + target.fraction * edge.length, edge.from)
        }
        if let reached = search.distance[edge.to], reached + (1 - target.fraction) * edge.length < (result?.distance ?? .infinity) {
            result = (reached + (1 - target.fraction) * edge.length, edge.to)
        }
        return result
    }
}

/// A queue that gives the smallest distance first.
private struct MinQueue {
    private var items: [(metres: Double, node: Int)] = []

    mutating func push(_ metres: Double, _ node: Int) {
        items.append((metres, node))
        var child = items.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard items[child].metres < items[parent].metres else { break }
            items.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> (Double, Int)? {
        guard let first = items.first else { return nil }
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var parent = 0
            while true {
                let left = parent * 2 + 1, right = left + 1
                var smallest = parent
                if left < items.count, items[left].metres < items[smallest].metres { smallest = left }
                if right < items.count, items[right].metres < items[smallest].metres { smallest = right }
                if smallest == parent { break }
                items.swapAt(parent, smallest)
                parent = smallest
            }
        }
        return (first.metres, first.node)
    }
}
