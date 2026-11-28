import Foundation
import GeoCore

/// An area of the world a map is wanted for: round a position, or round a route.
public struct MapArea: Equatable, Sendable, Identifiable {
    /// What the map is called when it is added, for example "Utrecht" or the name of a route.
    public var name: String
    public var box: BoundingBox

    /// The radius of a map round a position, in kilometres, when a caller does not choose one.
    public static let defaultRadiusKilometres = 10.0
    /// The room kept round a route, in kilometres, so someone who goes a little off the course still has a map.
    public static let routeMarginKilometres = 2.0
    /// The longest side of an area that is built on the phone, in kilometres. A bigger one needs a ready-made map.
    public static let maximumSideKilometres = 120.0

    public init(name: String, box: BoundingBox) {
        self.name = name
        self.box = box
    }

    /// A name and a box make an area: two areas with the same name and box are the same one.
    public var id: String { "\(name)|\(box.south)|\(box.west)|\(box.north)|\(box.east)" }

    /// The map round a position.
    ///
    /// - Parameters:
    ///   - coordinate: The middle.
    ///   - radiusKilometres: The distance from the middle to each side of the box, in kilometres.
    ///   - name: What the map is called.
    /// - Returns: The area, or `nil` where a circle can't be boxed (at the poles, over the antimeridian).
    public static func around(_ coordinate: Coordinate, radiusKilometres: Double = defaultRadiusKilometres, name: String) -> MapArea? {
        BoundingBox.around(coordinate, radiusKilometres: radiusKilometres).map { MapArea(name: name, box: $0) }
    }

    /// The map for a box with room round it, for a route.
    ///
    /// - Parameters:
    ///   - box: The area the route covers.
    ///   - marginKilometres: The room to add on every side, in kilometres.
    ///   - name: What the map is called.
    public static func covering(_ box: BoundingBox, marginKilometres: Double = routeMarginKilometres, name: String) -> MapArea {
        let latitudeMargin = marginKilometres / 111.32
        let middle = (box.south + box.north) / 2
        let longitudeMargin = marginKilometres / (111.32 * max(cos(middle * .pi / 180), 0.01))
        return MapArea(name: name, box: BoundingBox(
            south: max(box.south - latitudeMargin, -TileID.maximumLatitude), west: max(box.west - longitudeMargin, -180),
            north: min(box.north + latitudeMargin, TileID.maximumLatitude), east: min(box.east + longitudeMargin, 180)))
    }

    /// The length of the area's sides in kilometres: north to south, and west to east in the middle.
    public var sideKilometres: (northSouth: Double, westEast: Double) {
        let middle = (box.south + box.north) / 2
        return ((box.north - box.south) * 111.32, (box.east - box.west) * 111.32 * cos(middle * .pi / 180))
    }

    /// Whether the area is small enough to be built on a phone (``maximumSideKilometres``).
    public var fitsPhone: Bool {
        let sides = sideKilometres
        return max(sides.northSouth, sides.westEast) <= Self.maximumSideKilometres
    }

    /// Whether `bounds` holds the whole area.
    public func isCovered(by bounds: BoundingBox) -> Bool { bounds.encloses(box) }
}
