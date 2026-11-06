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
}
