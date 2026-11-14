import Testing

@testable import GeoCore

@Suite("Coordinate distance")
struct CoordinateDistanceTests {
    @Test("A degree of latitude is about 111.2 km, and a degree of longitude shrinks with the latitude")
    func degrees() {
        let a = Coordinate(latitude: 0, longitude: 0)
        #expect(abs(a.distance(to: Coordinate(latitude: 1, longitude: 0)) - 111_195) < 10)
        #expect(abs(a.distance(to: Coordinate(latitude: 0, longitude: 1)) - 111_195) < 10)
        let oslo = Coordinate(latitude: 60, longitude: 10)
        #expect(abs(oslo.distance(to: Coordinate(latitude: 60, longitude: 11)) - 55_597) < 20, "cos(60 degrees) is one half")
    }

    @Test("The distance is symmetric, zero to itself, and handles the antimeridian and the poles")
    func properties() {
        let a = Coordinate(latitude: 59.9, longitude: 10.7), b = Coordinate(latitude: 48.1, longitude: 11.6)
        #expect(a.distance(to: a) == 0)
        #expect(abs(a.distance(to: b) - b.distance(to: a)) < 1e-6)
        // Across the antimeridian the short way is taken.
        #expect(abs(Coordinate(latitude: 0, longitude: 179.5).distance(to: Coordinate(latitude: 0, longitude: -179.5)) - 111_195) < 10)
        #expect(abs(Coordinate(latitude: 90, longitude: 0).distance(to: Coordinate(latitude: -90, longitude: 0)) - Double.pi * Coordinate.earthRadius) < 1)
    }

    @Test("Oslo to Stockholm is about 417 km")
    func knownDistance() {
        let distance = Coordinate(latitude: 59.9139, longitude: 10.7522).distance(to: Coordinate(latitude: 59.3293, longitude: 18.0686))
        #expect(abs(distance - 417_000) < 3_000)
    }
}
