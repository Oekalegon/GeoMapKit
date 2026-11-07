import FeatureStore
import Testing

@testable import FeatureStoreBuilder

@Suite("Coastline joiner")
struct CoastlineJoinerTests {
    private func way(_ id: Int64, _ nodes: [Int64]) -> CoastlineJoiner.Way {
        CoastlineJoiner.Way(
            id: id, nodeIDs: nodes, points: nodes.map { PackedPoint(longitude: Int32($0) * 1000, latitude: Int32($0) * 10) })
    }

    @Test("Ways join head to tail, in the direction of the coastline")
    func joinsForward() {
        let result = CoastlineJoiner.join([way(2, [3, 4, 5]), way(1, [1, 2, 3]), way(3, [5, 6])])
        #expect(result.rings.isEmpty && result.chains.count == 1)
        #expect(result.chains[0].map { Int($0.longitude) / 1000 } == [1, 2, 3, 4, 5, 6])
    }

    @Test("A way that runs the other way is not reversed to fit")
    func neverReversed() {
        let result = CoastlineJoiner.join([way(1, [1, 2, 3]), way(2, [5, 4, 3])])
        #expect(result.chains.count == 2)
    }

    @Test("Ways that lead back to the start make a ring, and a closed way is a ring by itself")
    func rings() {
        let result = CoastlineJoiner.join([way(1, [1, 2, 3]), way(2, [3, 4, 1]), way(3, [7, 8, 9, 7])])
        #expect(result.chains.isEmpty && result.rings.count == 2)
        #expect(result.rings.contains { $0.count == 5 && $0.first == $0.last })
    }

    @Test("The result does not depend on the order of the input")
    func deterministic() {
        let input = [way(5, [1, 2]), way(3, [2, 3]), way(4, [2, 9]), way(9, [3, 4])]
        let forward = CoastlineJoiner.join(input), backward = CoastlineJoiner.join(input.reversed())
        #expect(forward.chains == backward.chains && forward.rings == backward.rings)
        // Way 3 has the lower ID of the two that leave node 2.
        #expect(forward.chains.contains { $0.count == 4 })
    }

    @Test("Degenerate ways are dropped")
    func degenerate() {
        let result = CoastlineJoiner.join([way(1, [1]), way(2, [4, 4]), way(3, [1, 2])])
        #expect(result.chains.count == 1 && result.rings.isEmpty)
    }
}
