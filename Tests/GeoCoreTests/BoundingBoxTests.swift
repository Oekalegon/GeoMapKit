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

    @Test("The box contains the whole circle")
    func containsCircle() throws {
        let tromso = Coordinate(latitude: 69.6492, longitude: 18.9553)
        let box = try #require(BoundingBox.around(tromso, radiusKilometres: 10))
        // Points just inside 10 km due east and due north (the edges touch the circle, so stay a hair inside).
        let kilometresPerDegree = 6371.0088 * Double.pi / 180
        let eastDegrees = 9.99 / (kilometresPerDegree * cos(tromso.latitude * .pi / 180))
        let northDegrees = 9.99 / kilometresPerDegree
        #expect(box.contains(Coordinate(latitude: tromso.latitude, longitude: tromso.longitude + eastDegrees)))
        #expect(box.contains(Coordinate(latitude: tromso.latitude, longitude: tromso.longitude - eastDegrees)))
        #expect(box.contains(Coordinate(latitude: tromso.latitude + northDegrees, longitude: tromso.longitude)))
        #expect(box.contains(Coordinate(latitude: tromso.latitude - northDegrees, longitude: tromso.longitude)))
        // A point 11 km north is outside.
        #expect(!box.contains(Coordinate(latitude: tromso.latitude + 11 / kilometresPerDegree, longitude: tromso.longitude)))
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
    }
}
