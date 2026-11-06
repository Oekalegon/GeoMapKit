import Foundation
import Testing
@testable import GeoCore

@Suite("TileID")
struct TileIDTests {
    @Test("Oslo and Tromsø fall in the expected z13 tiles")
    func knownNorwegianTiles() throws {
        let oslo = try #require(TileID.containing(Coordinate(latitude: 59.9139, longitude: 10.7522), zoom: 13))
        #expect(oslo.x == 4340)
        #expect(oslo.y == 2382)

        let tromso = try #require(TileID.containing(Coordinate(latitude: 69.6492, longitude: 18.9553), zoom: 13))
        #expect(tromso.x == 4527)
        #expect(tromso.y == 1856)
    }

    @Test("Zoom 0 is a single tile")
    func zoomZero() throws {
        let tile = try #require(TileID.containing(Coordinate(latitude: 60, longitude: 10), zoom: 0))
        #expect(tile.x == 0)
        #expect(tile.y == 0)
    }

    @Test("A coordinate on a tile border belongs to the east and south tile")
    func borderBelongsToEastAndSouth() throws {
        let tile = try #require(TileID.containing(Coordinate(latitude: 0, longitude: 0), zoom: 1))
        #expect(tile.x == 1)
        #expect(tile.y == 1)
    }

    @Test("The corners of a tile lie on its own borders")
    func cornersRoundTrip() throws {
        let tile = try #require(TileID(zoom: 13, x: 4340, y: 2382))
        let nw = tile.northWest
        let se = tile.southEast
        #expect(nw.latitude > se.latitude)
        #expect(nw.longitude < se.longitude)

        // The north-west corner is inside the same tile (borders belong to east and south).
        #expect(TileID.containing(nw, zoom: 13) == tile)

        // A point just inside the south-east corner is inside the tile too.
        let inside = Coordinate(latitude: se.latitude + 1e-7, longitude: se.longitude - 1e-7)
        #expect(TileID.containing(inside, zoom: 13) == tile)
    }

    @Test("A z13 tile is narrower in real distance at Norwegian latitudes")
    func tileWidthShrinksNorthwards() throws {
        func widthInKilometres(at latitude: Double) throws -> Double {
            let tile = try #require(TileID.containing(Coordinate(latitude: latitude, longitude: 10), zoom: 13))
            let degrees = tile.southEast.longitude - tile.northWest.longitude
            return degrees * 111.32 * cos(latitude * .pi / 180)
        }
        let equator = try widthInKilometres(at: 0)
        let oslo = try widthInKilometres(at: 59.9)
        #expect(equator > 4.5 && equator < 5.1)
        #expect(oslo > 2.2 && oslo < 2.6)
    }

    @Test("Latitudes beyond the Mercator limit are clamped")
    func latitudeClamped() throws {
        let north = try #require(TileID.containing(Coordinate(latitude: 90, longitude: 0), zoom: 5))
        #expect(north.y == 0)
        let south = try #require(TileID.containing(Coordinate(latitude: -90, longitude: 0), zoom: 5))
        #expect(south.y == 31)
    }

    @Test("Longitude wraps around the antimeridian")
    func longitudeWraps() throws {
        let east = try #require(TileID.containing(Coordinate(latitude: 0, longitude: 190), zoom: 3))
        let west = try #require(TileID.containing(Coordinate(latitude: 0, longitude: -170), zoom: 3))
        #expect(east == west)
    }

    @Test("Invalid input returns nil")
    func invalidInput() {
        #expect(TileID.containing(Coordinate(latitude: .nan, longitude: 0), zoom: 5) == nil)
        #expect(TileID.containing(Coordinate(latitude: 0, longitude: 0), zoom: -1) == nil)
        #expect(TileID.containing(Coordinate(latitude: 0, longitude: 0), zoom: 31) == nil)
        #expect(TileID(zoom: 2, x: 4, y: 0) == nil)
        #expect(TileID(zoom: 2, x: 0, y: -1) == nil)
    }
}
