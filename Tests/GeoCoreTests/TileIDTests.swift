import Foundation
import Testing
import GeoCore

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

    @Test("The equator and prime meridian (exactly representable) belong to the east and south tile")
    func exactBorderBelongsToEastAndSouth() throws {
        let tile = try #require(TileID.containing(Coordinate(latitude: 0, longitude: 0), zoom: 1))
        #expect(tile.x == 1)
        #expect(tile.y == 1)
    }

    @Test("Points just inside every corner of a tile map back to that tile")
    func insideCornersMapBack() throws {
        // Computed corners are NOT reliable (rounding), so test points strictly inside the tile.
        let epsilon = 1e-7
        for y in stride(from: 1800, to: 2500, by: 7) {
            for x in stride(from: 4300, to: 4600, by: 11) {
                let tile = try #require(TileID(zoom: 13, x: x, y: y))
                let nw = tile.northWest
                let se = tile.southEast
                #expect(nw.latitude > se.latitude)
                #expect(nw.longitude < se.longitude)

                let insideNW = Coordinate(latitude: nw.latitude - epsilon, longitude: nw.longitude + epsilon)
                let insideSE = Coordinate(latitude: se.latitude + epsilon, longitude: se.longitude - epsilon)
                #expect(TileID.containing(insideNW, zoom: 13) == tile)
                #expect(TileID.containing(insideSE, zoom: 13) == tile)
            }
        }
    }

    @Test("The last column ends at longitude 180")
    func lastColumnEndsAtAntimeridian() throws {
        let tile = try #require(TileID(zoom: 3, x: 7, y: 4))
        #expect(tile.southEast.longitude == 180)
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

    @Test("Longitude +180 is treated as -180 and falls in column 0")
    func plus180IsMinus180() throws {
        let plus = try #require(TileID.containing(Coordinate(latitude: 0, longitude: 180), zoom: 3))
        let minus = try #require(TileID.containing(Coordinate(latitude: 0, longitude: -180), zoom: 3))
        #expect(plus == minus)
        #expect(plus.x == 0)
        let justBefore = try #require(TileID.containing(Coordinate(latitude: 0, longitude: 179.999999), zoom: 3))
        #expect(justBefore.x == 7)
    }

    @Test("The highest zoom works")
    func maximumZoom() throws {
        let tile = try #require(TileID.containing(Coordinate(latitude: 59.9, longitude: 10.7), zoom: TileID.maximumZoom))
        #expect(tile.zoom == TileID.maximumZoom)
        #expect(tile.x < (1 << TileID.maximumZoom))
        #expect(tile.y < (1 << TileID.maximumZoom))
    }

    @Test("Invalid input returns nil")
    func invalidInput() {
        #expect(TileID.containing(Coordinate(latitude: .nan, longitude: 0), zoom: 5) == nil)
        #expect(TileID.containing(Coordinate(latitude: 0, longitude: 0), zoom: -1) == nil)
        #expect(TileID.containing(Coordinate(latitude: 0, longitude: 0), zoom: 31) == nil)
        #expect(TileID(zoom: 2, x: 4, y: 0) == nil)
        #expect(TileID(zoom: 2, x: 0, y: -1) == nil)
    }

    @Test("Encoding and decoding a tile round trips")
    func codableRoundTrip() throws {
        let tile = try #require(TileID(zoom: 13, x: 4340, y: 2382))
        let data = try JSONEncoder().encode(tile)
        #expect(try JSONDecoder().decode(TileID.self, from: data) == tile)
    }

    @Test("Decoding a tile outside the grid throws")
    func decodingInvalidTileThrows() {
        let invalid = [
            #"{"zoom":99,"x":-5,"y":123456789}"#,
            #"{"zoom":2,"x":4,"y":0}"#,
            #"{"zoom":2,"x":0,"y":-1}"#,
            #"{"zoom":-1,"x":0,"y":0}"#,
        ]
        for json in invalid {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(TileID.self, from: Data(json.utf8))
            }
        }
    }
}
