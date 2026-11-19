import FeatureStore
import Foundation
import GeoCore
import Testing

@testable import TrackMatching

/// Routes along a network between two positions on its edges.
@Suite("Network router")
struct NetworkRouterTests {
    /// 60 N, 10 E; one step is 0.0001 degrees (5.57 m east, 11.1 m north).
    private func packed(_ east: Double, _ north: Double) -> PackedPoint {
        PackedPoint(longitude: 100_000_000 + Int32((east * 1_000).rounded()), latitude: 600_000_000 + Int32((north * 1_000).rounded()))
    }

    private func way(_ id: Int64, _ points: [(Double, Double)]) -> StoredFeature {
        StoredFeature(
            classID: FeatureClass.path.rawValue, kind: .line, objectType: .way, objectID: id, parts: [GeometryPart(points: points.map { packed($0.0, $0.1) })])
    }

    private func spot(_ network: LineNetwork, _ east: Double, _ north: Double) throws -> EdgeProjection {
        try #require(network.edges(near: Coordinate(latitude: 60 + north * 0.0001, longitude: 10 + east * 0.0001), within: 3).first)
    }

    /// An L: a way east for 50 steps, then north for 40 steps from its end.
    private func corner() -> LineNetwork { LineNetwork(features: [way(1, [(0, 0), (50, 0)]), way(2, [(50, 0), (50, 40)])]) }

    @Test("On one edge the distance is the part of the edge between the two, whichever way round")
    func sameEdge() throws {
        let network = corner()
        var router = NetworkRouter(network: network, hopDistance: 0)
        let a = try spot(network, 10, 0), b = try spot(network, 30, 0)
        let forward = router.search(from: a, limit: 500), backward = router.search(from: b, limit: 500)
        let there = try #require(router.distance(in: forward, from: a, to: b))
        let back = try #require(router.distance(in: backward, from: b, to: a))
        #expect(abs(there - 20 * 5.57) < 1 && abs(there - back) < 1e-6)
        #expect(try #require(router.route(in: forward, from: a, to: b)).edges == [0])
    }

    @Test("Around a corner the route has the edges in order, the node it passes, and the length along them")
    func aroundACorner() throws {
        let network = corner()
        var router = NetworkRouter(network: network, hopDistance: 0)
        let a = try spot(network, 40, 0), b = try spot(network, 50, 20)
        let search = router.search(from: a, limit: 500)
        let route = try #require(router.route(in: search, from: a, to: b))
        #expect(abs(route.distance - (10 * 5.57 + 20 * 11.12)) < 2)
        #expect(route.edges == [0, 1])
        #expect(route.nodes.contains { abs(network.coordinates[$0].longitude - 10.005) < 1e-6 && abs(network.coordinates[$0].latitude - 60) < 1e-6 })
    }

    @Test("A search stops at its limit: a target just inside is found and one just beyond is not")
    func limit() throws {
        let network = corner()
        var router = NetworkRouter(network: network, hopDistance: 0)
        let a = try spot(network, 40, 0), b = try spot(network, 50, 20)
        let needed = 10 * 5.57 + 20 * 11.12   // 278 m
        #expect(router.distance(in: router.search(from: a, limit: needed + 5), from: a, to: b) != nil)
        #expect(router.distance(in: router.search(from: a, limit: needed - 20), from: a, to: b) == nil)
        #expect(router.route(in: router.search(from: a, limit: needed - 20), from: a, to: b) == nil)
    }

    @Test("Two dead ends a metre apart are joined by a hop, and not when the hop distance is 0")
    func hop() throws {
        let network = LineNetwork(features: [way(1, [(0, 0), (50, 0)]), way(2, [(50.2, 0), (100, 0)])])
        let a = try spot(network, 40, 0), b = try spot(network, 60, 0)
        var bridged = NetworkRouter(network: network, hopDistance: 3)
        let route = try #require(bridged.route(in: bridged.search(from: a, limit: 500), from: a, to: b))
        #expect(route.edges == [0, 1] && abs(route.distance - 20 * 5.57) < 3)
        var apart = NetworkRouter(network: network, hopDistance: 0)
        #expect(apart.distance(in: apart.search(from: a, limit: 500), from: a, to: b) == nil)
    }
}
