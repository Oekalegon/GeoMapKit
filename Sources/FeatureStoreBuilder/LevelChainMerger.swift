import FeatureStore
import Foundation
import GeoCore

/// A chain of a line feature of a level: where it came from and its points.
struct LevelChain {
    var key: LevelKey
    var attributes: LevelAttributes
    var line: [PackedPoint]
}

/// Joins the chains of a level that continue each other into one (the ways of a road between two junctions into the road).
///
/// A road is hundreds of ways, each with a few points. Written one by one every way is a feature of its own, with its own header
/// in the cell, and at a low zoom that is most of the file. Two chains are one where they meet at a point at which no other
/// chain of the group ends: the group is the class, the subclass (with the bridge and tunnel bits) and the name, so a road that
/// changes its name, its grade or goes over a bridge is not joined across. A junction (three or more chains) joins nothing.
/// The joined line is written under the key of its first chain. Where a chain has to be turned round to continue the next, it is.
enum LevelChainMerger {
    /// - Parameter chains: The chains of a level block, in a fixed order.
    /// - Returns: The chains with the continuing ones joined, in the order of their first chain.
    static func merge(_ chains: [LevelChain]) -> [LevelChain] {
        struct Group: Hashable {
            var classID: UInt8
            var subclass: UInt8
            var name: String?
        }
        struct End: Hashable {
            var group: Group
            var point: PackedPoint
        }
        struct Attachment {
            var chain: Int
            var atStart: Bool
        }
        func group(of chain: LevelChain) -> Group {
            Group(classID: chain.key.classID, subclass: chain.attributes.subclass, name: chain.attributes.name)
        }
        var ends: [End: [Attachment]] = [:]
        for (index, chain) in chains.enumerated() where chain.line.count >= 2 {
            let g = group(of: chain)
            if let first = chain.line.first { ends[End(group: g, point: first), default: []].append(Attachment(chain: index, atStart: true)) }
            if let last = chain.line.last { ends[End(group: g, point: last), default: []].append(Attachment(chain: index, atStart: false)) }
        }
        // The neighbour at each end of a chain: the one other chain that ends at the same point (a chain that begins and ends at the
        // same point is a loop and joins nothing at that point).
        func neighbour(of index: Int, atStart: Bool) -> Attachment? {
            let chain = chains[index]
            guard let point = atStart ? chain.line.first : chain.line.last,
                let list = ends[End(group: group(of: chain), point: point)], list.count == 2
            else { return nil }
            let other = list.first { !($0.chain == index && $0.atStart == atStart) }
            guard let other, other.chain != index else { return nil }
            return other
        }
        var visited = [Bool](repeating: false, count: chains.count)
        var merged: [LevelChain] = []
        /// Follows the chains from one end of `index` outwards, collecting the points in order.
        func walk(from index: Int, enteringAtStart: Bool) -> [PackedPoint] {
            var points: [PackedPoint] = []
            var current = index
            var atStart = enteringAtStart
            while !visited[current] {
                visited[current] = true
                let line = atStart ? chains[current].line : chains[current].line.reversed()
                points.append(contentsOf: points.isEmpty ? line[...] : line.dropFirst())
                guard let next = neighbour(of: current, atStart: !atStart) else { break }
                current = next.chain
                atStart = next.atStart
            }
            return points
        }
        // The chains that have a free end first, so a path is followed from its beginning; what is left are closed loops.
        for index in chains.indices where !visited[index] && chains[index].line.count >= 2 {
            if neighbour(of: index, atStart: true) == nil {
                var chain = chains[index]
                chain.line = walk(from: index, enteringAtStart: true)
                merged.append(chain)
            } else if neighbour(of: index, atStart: false) == nil {
                var chain = chains[index]
                chain.line = walk(from: index, enteringAtStart: false)
                merged.append(chain)
            }
        }
        for index in chains.indices where !visited[index] {
            var chain = chains[index]
            if chain.line.count >= 2 { chain.line = walk(from: index, enteringAtStart: true) }
            merged.append(chain)
        }
        return merged
    }

    /// For every chain, the extent of the network it belongs to: the chains of one class that share an end point. Extent is the
    /// diagonal of the bounding box in projected radians, as ``extent(_:)``.
    ///
    /// - Parameter chains: The class and the points of each chain.
    /// - Returns: One extent per chain, in the order of `chains`.
    static func networkExtents(of chains: [(classID: UInt8, line: [PackedPoint])]) -> [Double] {
        var parent = Array(chains.indices)
        func root(_ index: Int) -> Int {
            var current = index
            while parent[current] != current {
                parent[current] = parent[parent[current]]
                current = parent[current]
            }
            return current
        }
        struct EndKey: Hashable { var classID: UInt8; var point: PackedPoint }
        var firstAtEnd: [EndKey: Int] = [:]
        for (index, chain) in chains.enumerated() {
            for point in [chain.line.first, chain.line.last] {
                guard let point else { continue }
                let key = EndKey(classID: chain.classID, point: point)
                if let other = firstAtEnd[key] { parent[root(index)] = root(other) } else { firstAtEnd[key] = index }
            }
        }
        // The bounding box of each network, in degrees of longitude and projected latitude.
        var boxes: [Int: (minX: Double, maxX: Double, minY: Double, maxY: Double)] = [:]
        for (index, chain) in chains.enumerated() {
            let group = root(index)
            var box = boxes[group] ?? (Double.infinity, -Double.infinity, Double.infinity, -Double.infinity)
            for point in chain.line {
                let x = Double(point.longitude), y = Mercator.y(latitude: Double(point.latitude))
                box = (min(box.minX, x), max(box.maxX, x), min(box.minY, y), max(box.maxY, y))
            }
            boxes[group] = box
        }
        return chains.indices.map { index in
            guard let box = boxes[root(index)] else { return 0 }
            return hypot((box.maxX - box.minX) * .pi / 180 / 1e7, box.maxY - box.minY)
        }
    }
}
