import Foundation
import Testing
import GeoCore
#if canImport(CoreLocation)
import CoreLocation
#endif

@Suite("Coordinate")
struct CoordinateTests {
    @Test("Valid coordinates, including the extremes, are valid")
    func validCoordinates() {
        #expect(Coordinate(latitude: 59.9139, longitude: 10.7522).isValid)
        #expect(Coordinate(latitude: 90, longitude: 180).isValid)
        #expect(Coordinate(latitude: -90, longitude: -180).isValid)
    }

    @Test("Out-of-range and non-finite coordinates are not valid but can be created")
    func invalidCoordinates() {
        #expect(!Coordinate(latitude: 90.0001, longitude: 0).isValid)
        #expect(!Coordinate(latitude: 0, longitude: 180.0001).isValid)
        #expect(!Coordinate(latitude: .nan, longitude: 0).isValid)
        #expect(!Coordinate(latitude: 0, longitude: .infinity).isValid)
    }

    @Test("Encoding and decoding a coordinate round trips")
    func codableRoundTrip() throws {
        let coordinate = Coordinate(latitude: 69.6492, longitude: 18.9553)
        let data = try JSONEncoder().encode(coordinate)
        #expect(try JSONDecoder().decode(Coordinate.self, from: data) == coordinate)
    }

    @Test("Equal coordinates have equal hashes")
    func hashable() {
        let a = Coordinate(latitude: 1, longitude: 2)
        let b = Coordinate(latitude: 1, longitude: 2)
        #expect(Set([a, b]).count == 1)
    }

    #if canImport(CoreLocation)
    @Test("Conversion to and from CoreLocation keeps latitude and longitude in order")
    func coreLocationRoundTrip() {
        let coordinate = Coordinate(latitude: 59.9139, longitude: 10.7522)
        let cl = coordinate.clLocationCoordinate
        #expect(cl.latitude == 59.9139)
        #expect(cl.longitude == 10.7522)
        #expect(Coordinate(cl) == coordinate)
    }
    #endif
}
