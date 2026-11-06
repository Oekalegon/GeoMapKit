import Foundation
import Testing
import GeoCore

@Suite("BoundingBox")
struct BoundingBoxTests {
    private let box = BoundingBox(south: 59, west: 10, north: 60, east: 11)

    @Test("Contains points inside and on the edges")
    func containsInsideAndEdges() {
        #expect(box.contains(Coordinate(latitude: 59.5, longitude: 10.5)))
        #expect(box.contains(Coordinate(latitude: 59, longitude: 10)))
        #expect(box.contains(Coordinate(latitude: 60, longitude: 11)))
    }

    @Test("Does not contain points outside or non-finite points")
    func excludesOutside() {
        #expect(!box.contains(Coordinate(latitude: 58.999, longitude: 10.5)))
        #expect(!box.contains(Coordinate(latitude: 59.5, longitude: 11.001)))
        #expect(!box.contains(Coordinate(latitude: .nan, longitude: 10.5)))
    }

    @Test("Validity")
    func validity() {
        #expect(box.isValid)
        #expect(!BoundingBox(south: 60, west: 10, north: 59, east: 11).isValid)
        #expect(!BoundingBox(south: 59, west: 11, north: 60, east: 10).isValid)
        #expect(!BoundingBox(south: 59, west: 10, north: 91, east: 11).isValid)
        #expect(!BoundingBox(south: .nan, west: 10, north: 60, east: 11).isValid)
    }

    @Test("A box around a point is centred on it and wider in longitude at high latitudes")
    func around() throws {
        let oslo = Coordinate(latitude: 59.9139, longitude: 10.7522)
        let box = try #require(BoundingBox.around(oslo, radiusKilometres: 15))
        #expect(abs((box.south + box.north) / 2 - oslo.latitude) < 1e-9)
        #expect(abs((box.west + box.east) / 2 - oslo.longitude) < 1e-9)
        // 15 km north-south is about 0.27 degrees each side.
        #expect(abs((box.north - box.south) / 2 - 15 / 111.195) < 1e-3)
        // At 60 degrees north a degree of longitude is about half as long, so the box is twice as wide in degrees.
        let widthRatio = (box.east - box.west) / (box.north - box.south)
        #expect(widthRatio > 1.9 && widthRatio < 2.1)
        #expect(box.isValid)
        #expect(box.contains(oslo))
    }

    @Test("The box contains every point of the circle, at small and very large radii")
    func containsCircle() throws {
        let earthRadius = 6371.0088
        for (latitude, radius) in [(69.6492, 10.0), (60.0, 15.0), (60.0, 200.0), (60.0, 2000.0), (70.0, 2000.0), (0.0, 500.0)] {
            let center = Coordinate(latitude: latitude, longitude: 18.0)
            let box = try #require(BoundingBox.around(center, radiusKilometres: radius))
            let delta = radius / earthRadius
            let phi = latitude * .pi / 180
            // Walk the circle: the point at distance `radius` on each bearing.
            for bearingDegrees in stride(from: 0.0, to: 360.0, by: 1.0) {
                let theta = bearingDegrees * .pi / 180
                let phi2 = asin(sin(phi) * cos(delta) + cos(phi) * sin(delta) * cos(theta))
                let lambda2 = atan2(sin(theta) * sin(delta) * cos(phi), cos(delta) - sin(phi) * sin(phi2))
                let point = Coordinate(latitude: phi2 * 180 / .pi, longitude: 18.0 + lambda2 * 180 / .pi)
                // The extreme points lie exactly on the box edge, so allow for rounding.
                let tolerance = 1e-9
                #expect(
                    point.latitude >= box.south - tolerance && point.latitude <= box.north + tolerance
                        && point.longitude >= box.west - tolerance && point.longitude <= box.east + tolerance,
                    "lat \(latitude), radius \(radius) km, bearing \(bearingDegrees)"
                )
            }
            // The box is not much bigger than needed: its north edge is exactly the radius away.
            #expect(abs((box.north - center.latitude) * .pi / 180 * earthRadius - radius) < 1e-6)
        }
    }

    @Test("Invalid input, the poles and the antimeridian give nil")
    func aroundRejects() {
        let origin = Coordinate(latitude: 60, longitude: 10)
        #expect(BoundingBox.around(origin, radiusKilometres: 0) == nil)
        #expect(BoundingBox.around(origin, radiusKilometres: -1) == nil)
        #expect(BoundingBox.around(origin, radiusKilometres: .nan) == nil)
        #expect(BoundingBox.around(Coordinate(latitude: .nan, longitude: 0), radiusKilometres: 1) == nil)
        #expect(BoundingBox.around(Coordinate(latitude: 89.9, longitude: 0), radiusKilometres: 50) == nil)
        #expect(BoundingBox.around(Coordinate(latitude: 0, longitude: 179.9), radiusKilometres: 50) == nil)
        // A circle that contains the pole spans every longitude.
        #expect(BoundingBox.around(Coordinate(latitude: 80, longitude: 0), radiusKilometres: 1500) == nil)
        // A radius of more than a quarter of the Earth.
        #expect(BoundingBox.around(Coordinate(latitude: 0, longitude: 0), radiusKilometres: 12_000) == nil)
    }
}
