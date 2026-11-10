import FeatureStore
import Testing

@testable import FeatureStoreBuilder

/// The point of an area that is farthest from its edges.
@Suite("Polygon pole")
struct PolygonPoleTests {
    private func ring(_ points: [(Double, Double)]) -> [PackedPoint] {
        // Degrees to packed points; (longitude, latitude), closed.
        var packed = points.map { PackedPoint(longitude: Int32($0.0 * 1e7), latitude: Int32($0.1 * 1e7)) }
        if let first = packed.first, packed.last != first { packed.append(first) }
        return packed
    }

    private func degrees(_ point: PackedPoint) -> (Double, Double) { (Double(point.longitude) / 1e7, Double(point.latitude) / 1e7) }

    @Test("A square has its pole in the middle")
    func square() throws {
        let pole = try #require(PolygonPole.find(in: [ring([(5, 52), (5.001, 52), (5.001, 52.001), (5, 52.001)])]))
        let (lon, lat) = degrees(pole)
        #expect(abs(lon - 5.0005) < 0.0001 && abs(lat - 52.0005) < 0.0001)
    }

    @Test("An L shape has its pole inside the thick arm, not at the middle of its box, which lies outside")
    func lShape() throws {
        // A box 10 by 10 units of 0.001 degrees with the north-east quarter and more cut out; the middle of the box is outside.
        let u = 0.001
        let l = ring([(0, 0), (10 * u, 0), (10 * u, 2 * u), (2 * u, 2 * u), (2 * u, 10 * u), (0, 10 * u)].map { ($0.0 + 5, $0.1 + 52) })
        let pole = try #require(PolygonPole.find(in: [l]))
        let (lon, lat) = degrees(pole)
        let insideArm = (lon < 5 + 2 * u && lat < 52 + 10 * u) || (lat < 52 + 2 * u && lon < 5 + 10 * u)
        #expect(insideArm, "inside the L")
        #expect(!(abs(lon - (5 + 5 * u)) < 0.0005 && abs(lat - (52 + 5 * u)) < 0.0005), "not the middle of the box")
    }

    @Test("A hole is outside: the pole of a ring around a pond is not in the pond")
    func hole() throws {
        let outer = ring([(5, 52), (5.01, 52), (5.01, 52.01), (5, 52.01)])
        let pond = ring([(5.003, 52.003), (5.007, 52.003), (5.007, 52.007), (5.003, 52.007)])
        let pole = try #require(PolygonPole.find(in: [outer, pond]))
        let (lon, lat) = degrees(pole)
        let inPond = lon > 5.003 && lon < 5.007 && lat > 52.003 && lat < 52.007
        #expect(!inPond)
    }

    @Test("Rings with no area, and no rings, have no pole")
    func degenerate() {
        #expect(PolygonPole.find(in: []) == nil)
        #expect(PolygonPole.find(in: [ring([(5, 52), (5.001, 52)])]) == nil)
        #expect(PolygonPole.find(in: [ring([(5, 52), (5.001, 52), (5.002, 52)])]) == nil, "a line is no area")
    }

    @Test("Far from the equator the pole is in the middle of a square on the ground, not of the degrees")
    func highLatitude() throws {
        // At 65 N a degree of longitude is 0.42 of a degree of latitude: this box is as wide on the ground as it is high.
        let width = 0.001 / 0.4226
        let pole = try #require(PolygonPole.find(in: [ring([(10, 65), (10 + width, 65), (10 + width, 65.001), (10, 65.001)])]))
        let (lon, lat) = degrees(pole)
        #expect(abs(lon - (10 + width / 2)) < width / 20 && abs(lat - 65.0005) < 0.0001)
    }
}
