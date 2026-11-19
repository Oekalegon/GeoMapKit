import FeatureStore
import Foundation
import GeoCore
import Testing

@testable import TrackMatching

/// The network of lines that a track is matched to.
@Suite("Line network")
struct LineNetworkTests {
    /// A point at `east` and `north` steps of 0.001 degrees (about 111 m of latitude) from 60 N, 10 E.
    private func point(_ east: Int, _ north: Int) -> PackedPoint {
        PackedPoint(longitude: 100_000_000 + Int32(east) * 10_000, latitude: 600_000_000 + Int32(north) * 10_000)
    }

    private func way(_ id: Int64, _ points: [PackedPoint], _ classID: FeatureClass = .path, kind: FeatureKind = .line) -> StoredFeature {
        StoredFeature(classID: classID.rawValue, kind: kind, objectType: .way, objectID: id, parts: [GeometryPart(points: points)])
    }

    @Test("Lines that share a vertex meet there: a T junction has a node with three edges")
    func junction() {
        let network = LineNetwork(features: [way(1, [point(0, 0), point(1, 0), point(2, 0)]), way(2, [point(1, 0), point(1, 1)])])
        #expect(network.coordinates.count == 4 && network.edges.count == 3)
        let junction = network.coordinates.firstIndex { abs($0.longitude - 10.001) < 1e-9 && abs($0.latitude - 60.0) < 1e-9 }
        #expect(junction != nil && network.incident[junction!].count == 3)
        #expect(Set(network.incident[junction!].map { network.edges[$0].wayID }) == [1, 2])
    }

    @Test("An edge has the length of its step in metres, on the sphere")
    func length() throws {
        let network = LineNetwork(features: [way(1, [point(0, 0), point(0, 1)])])
        let edge = try #require(network.edges.first)
        #expect(abs(edge.length - 111.2) < 0.2)
        let across = LineNetwork(features: [way(1, [point(0, 0), point(1, 0)])])
        #expect(abs(across.edges[0].length - 111.2 * cos(60 * Double.pi / 180)) < 0.2, "a step of longitude is shorter at 60 degrees north")
    }

    @Test("Steps of no length and steps that are stored twice are left out")
    func degenerate() {
        let twice = LineNetwork(features: [way(1, [point(0, 0), point(0, 0), point(1, 0)]), way(1, [point(1, 0), point(0, 0)])])
        #expect(twice.edges.count == 1, "the repeated vertex and the same step stored again for the same way give one edge")
        let two = LineNetwork(features: [way(1, [point(0, 0), point(1, 0)]), way(2, [point(0, 0), point(1, 0)])])
        #expect(two.edges.count == 2, "two ways over the same step stay two edges")
    }

    @Test("Only line features of the chosen classes count")
    func classes() {
        let path = way(1, [point(0, 0), point(1, 0)])
        let stream = way(2, [point(0, 1), point(1, 1)], .waterLine)
        let wood = way(3, [point(0, 2), point(1, 2), point(1, 3), point(0, 2)], .forest, kind: .area)
        let road = way(4, [point(0, 3), point(1, 3)], .roadMajor)
        let features = [path, stream, wood, road]
        #expect(Set(LineNetwork(features: features).edges.map(\.wayID)) == [1, 4])
        #expect(Set(LineNetwork(features: features, classes: [FeatureClass.waterLine.rawValue]).edges.map(\.wayID)) == [2])
        #expect(LineNetwork(features: []).edges.isEmpty)
    }

    @Test("The parts of a way cut at a cell border are joined where they meet")
    func cellBorder() {
        let left = way(1, [point(0, 0), point(5, 0)])
        let right = way(1, [point(5, 0), point(9, 0)])
        let network = LineNetwork(features: [left, right])
        #expect(network.coordinates.count == 3 && network.edges.count == 2)
        let middle = network.edges[0].to
        #expect(network.otherEnd(of: 1, from: middle) == network.edges[1].to)
        #expect(network.incident[middle].count == 2)
    }

    @Test("The nearest edges to a position come with the nearest point, how far along it lies and the distance")
    func nearby() throws {
        let network = LineNetwork(features: [way(1, [point(0, 0), point(10, 0)]), way(2, [point(0, 1), point(10, 1)])])
        // 30 m north of the first line, a quarter of the way along it.
        let here = Coordinate(latitude: 60.0 + 30 / 111_195, longitude: 10.0 + 0.0025)
        let found = network.edges(near: here, within: 100)
        #expect(found.count == 2 && found[0].distance < found[1].distance)
        let first = try #require(found.first)
        #expect(network.edges[first.edge].wayID == 1)
        #expect(abs(first.distance - 30) < 0.5 && abs(first.fraction - 0.25) < 0.01)
        #expect(abs(first.coordinate.latitude - 60.0) < 1e-6 && abs(first.coordinate.longitude - here.longitude) < 1e-6)
        #expect(network.edges(near: here, within: 20).isEmpty)
        #expect(network.edges(near: here, within: 0).isEmpty)
        #expect(network.edges(near: here, within: 60).count == 1, "the second line is 81 m away")
    }

    @Test("A position beyond the end of an edge is projected on its end point")
    func beyondEnd() throws {
        let network = LineNetwork(features: [way(1, [point(0, 0), point(1, 0)])])
        let found = try #require(network.edges(near: Coordinate(latitude: 60.0, longitude: 10.0 - 0.0005), within: 100).first)
        #expect(found.fraction == 0 && abs(found.distance - 27.8) < 0.5)
    }

    @Test("A long edge is found from any bucket along it")
    func longEdge() {
        let network = LineNetwork(features: [way(1, [point(0, 0), point(400, 400)])])  // 44 km of latitude
        for step in [0, 123, 399] {
            let here = Coordinate(latitude: 60.0 + Double(step) * 0.001 + 0.0001, longitude: 10.0 + Double(step) * 0.001)
            #expect(network.edges(near: here, within: 50).count == 1, "step \(step)")
        }
    }

    @Test("A long diagonal edge does not fill its whole box in the index")
    func longEdgeIndex() {
        let network = LineNetwork(features: [way(1, [point(0, 0), point(400, 400)])])  // 800 x 800 buckets in the box
        #expect(network.indexEntryCount < 20_000, "the index has \(network.indexEntryCount) entries")
        // Every point along it finds it, also between two steps and close to the radius.
        for step in stride(from: 0, through: 400, by: 7) {
            let along = Coordinate(latitude: 60.0 + Double(step) * 0.001, longitude: 10.0 + Double(step) * 0.001)
            let beside = Coordinate(latitude: along.latitude + 40 / 111_195, longitude: along.longitude)
            #expect(network.edges(near: beside, within: 45).count == 1, "step \(step)")
        }
    }

    @Test("South of the equator and west of Greenwich the buckets are right too")
    func southWest() {
        func spot(_ east: Int, _ north: Int) -> PackedPoint {
            PackedPoint(longitude: -700_000_000 + Int32(east) * 10_000, latitude: -330_000_000 + Int32(north) * 10_000)  // 33 S, 70 W
        }
        let network = LineNetwork(features: [way(1, [spot(0, 0), spot(10, 0)]), way(2, [spot(0, -1), spot(10, -1)])])
        let here = Coordinate(latitude: -33.0 - 0.0002, longitude: -70.0 + 0.005)
        // 22 m from the first line and 89 m from the second.
        let near = network.edges(near: here, within: 40)
        #expect(near.count == 1 && network.edges[near[0].edge].wayID == 1 && abs(near[0].distance - 22.2) < 0.5)
        let both = network.edges(near: here, within: 100)
        #expect(both.count == 2 && network.edges[both[1].edge].wayID == 2 && abs(both[1].distance - 88.9) < 1)
    }

    @Test("An invalid position finds nothing")
    func invalidPosition() {
        let network = LineNetwork(features: [way(1, [point(0, 0), point(1, 0)])])
        #expect(network.edges(near: Coordinate(latitude: .nan, longitude: 10), within: 50).isEmpty)
        #expect(network.edges(near: Coordinate(latitude: 60, longitude: 10), within: .infinity).isEmpty)
    }

    // MARK: From a map

    /// A store with a road across two cells that meet at the border, and a path in a cell far away.
    private func store() throws -> (FeatureStoreFile, BoundingBox) {
        var writer = FeatureStoreWriter(boundingBox: BoundingBox(south: 59.9, west: 9.9, north: 60.1, east: 10.1), attribution: "© OpenStreetMap contributors, ODbL")
        let west = try #require(TileID.containing(Coordinate(latitude: 60.0, longitude: 10.0), zoom: 13))
        let east = try #require(TileID(zoom: 13, x: west.x + 1, y: west.y))
        let border = Int32((west.southEast.longitude * 1e7).rounded())
        let lat = Int32(((west.northWest.latitude + west.southEast.latitude) / 2 * 1e7).rounded())
        try writer.add(
            StoredFeature(classID: FeatureClass.roadMinor.rawValue, kind: .line, objectType: .way, objectID: 7,
                parts: [GeometryPart(points: [PackedPoint(longitude: border - 4_000, latitude: lat), PackedPoint(longitude: border, latitude: lat)])]),
            band: .detail, cell: west)
        try writer.add(
            StoredFeature(classID: FeatureClass.roadMinor.rawValue, kind: .line, objectType: .way, objectID: 7, offsetAlongLine: 100,
                parts: [GeometryPart(points: [PackedPoint(longitude: border, latitude: lat), PackedPoint(longitude: border + 4_000, latitude: lat)])]),
            band: .detail, cell: east)
        let far = try #require(TileID(zoom: 13, x: west.x + 50, y: west.y))
        try writer.add(
            StoredFeature(classID: FeatureClass.path.rawValue, kind: .line, objectType: .way, objectID: 9,
                parts: [GeometryPart(points: [PackedPoint(longitude: border + 500_000, latitude: lat), PackedPoint(longitude: border + 504_000, latitude: lat)])]),
            band: .detail, cell: far)
        let box = BoundingBox(south: west.southEast.latitude, west: west.northWest.longitude, north: west.northWest.latitude, east: east.southEast.longitude)
        return (try FeatureStoreFile(data: try writer.data()), box)
    }

    @Test("A network from a map reads the cells of the box and joins a way across their border")
    func fromSource() throws {
        let (file, box) = try store()
        let network = try LineNetwork(source: file, box: box)
        #expect(network.edges.count == 2 && network.coordinates.count == 3, "the far path is outside the box")
        #expect(network.edges.allSatisfy { $0.wayID == 7 && $0.classID == FeatureClass.roadMinor.rawValue })
        #expect(network.incident.map(\.count).sorted() == [1, 1, 2])
    }

    @Test("A box that is invalid or too large is refused")
    func refused() throws {
        let (file, _) = try store()
        #expect(throws: LineNetworkError.invalidBox) { try LineNetwork(source: file, box: BoundingBox(south: 61, west: 10, north: 60, east: 11)) }
        #expect(throws: LineNetworkError.self) { try LineNetwork(source: file, box: BoundingBox(south: 40, west: 0, north: 70, east: 30)) }
    }
}
