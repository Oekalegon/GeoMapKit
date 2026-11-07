import FeatureStore
import Foundation
import GeoCore

@testable import FeatureStoreBuilder

/// A deterministic random generator so failures reproduce.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A 3 by 3 block of cells around a centre cell near Liechtenstein, with a way to place points by cell fractions.
struct Block {
    let centre = TileID(zoom: 13, x: 4_312, y: 2_848)!
    let rect: CellRect
    let west: Double, east: Double, northY: Double, southY: Double

    init() {
        rect = CellRect(tile: centre)
        let outer = (
            CellRect(tile: TileID(zoom: 13, x: 4_311, y: 2_847)!), CellRect(tile: TileID(zoom: 13, x: 4_313, y: 2_849)!)
        )
        west = Double(outer.0.west)
        east = Double(outer.1.east)
        northY = outer.0.northY
        southY = outer.1.southY
    }

    /// A point at fractions (0...3, 0...3) of the block, from its north-west corner.
    func point(_ fx: Double, _ fy: Double) -> PackedPoint {
        let longitude = west + fx / 3 * (east - west)
        let y = northY + fy / 3 * (southY - northY)
        return PackedPoint(longitude: Int32(longitude.rounded()), latitude: Int32(Mercator.latitude(y: y).rounded()))
    }

    func tile(column: Int, row: Int) -> TileID { TileID(zoom: 13, x: centre.x - 1 + column, y: centre.y - 1 + row)! }
}

/// The length of a polyline in metres.
func length(_ points: [PackedPoint]) -> Double {
    zip(points, points.dropFirst()).reduce(0) { $0 + Geodesy.distance($1.0, $1.1) }
}

/// The area of a ring in projected radians squared (the shoelace formula in Web Mercator).
func projectedArea(_ ring: [PackedPoint]) -> Double {
    var sum = 0.0
    for (a, b) in zip(ring, ring.dropFirst()) {
        let ax = Mercator.radians(longitude: Double(a.longitude)), ay = Mercator.y(latitude: Double(a.latitude))
        let bx = Mercator.radians(longitude: Double(b.longitude)), by = Mercator.y(latitude: Double(b.latitude))
        sum += ax * by - bx * ay
    }
    return abs(sum) / 2
}
