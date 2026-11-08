import Foundation
import GeoCore

/// One polygon of a region outline: an outer ring and the holes cut out of it.
///
/// Rings are lists of vertices in degrees; the closing vertex (the same as the first) is not stored.
public struct RegionPolygon: Hashable, Sendable {
    /// The outer ring.
    public let outer: [Coordinate]
    /// The holes, each a ring inside the outer one.
    public let holes: [[Coordinate]]

    /// Creates a polygon.
    ///
    /// - Parameters:
    ///   - outer: The outer ring, at least 3 vertices.
    ///   - holes: The holes.
    public init(outer: [Coordinate], holes: [[Coordinate]] = []) {
        self.outer = outer
        self.holes = holes
    }

    /// Whether a coordinate lies inside the polygon: inside the outer ring and in no hole. Points on an edge may fall either way.
    ///
    /// The test treats longitude and latitude as plane coordinates, which is right for the small, simplified outlines of regions
    /// that do not cross the antimeridian.
    ///
    /// - Parameter coordinate: The position to test.
    public func contains(_ coordinate: Coordinate) -> Bool {
        Self.ring(outer, contains: coordinate) && !holes.contains { Self.ring($0, contains: coordinate) }
    }

    /// The absolute area of the outer ring minus the holes, in square degrees, with longitudes scaled by the cosine of the mean
    /// latitude. It is only for ordering regions by size, not a measurement.
    public var approximateArea: Double {
        let scale = cos((outer.reduce(0) { $0 + $1.latitude } / Double(max(outer.count, 1))) * .pi / 180)
        return max(Self.shoelace(outer) - holes.reduce(0) { $0 + Self.shoelace($1) }, 0) * scale
    }

    private static func ring(_ ring: [Coordinate], contains point: Coordinate) -> Bool {
        var inside = false
        var previous = ring.count - 1
        for index in ring.indices {
            let a = ring[index], b = ring[previous]
            if (a.latitude > point.latitude) != (b.latitude > point.latitude),
                point.longitude < (b.longitude - a.longitude) * (point.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude
            {
                inside.toggle()
            }
            previous = index
        }
        return inside
    }

    private static func shoelace(_ ring: [Coordinate]) -> Double {
        var sum = 0.0
        var previous = ring.count - 1
        for index in ring.indices {
            sum += ring[previous].longitude * ring[index].latitude - ring[index].longitude * ring[previous].latitude
            previous = index
        }
        return abs(sum) / 2
    }
}
