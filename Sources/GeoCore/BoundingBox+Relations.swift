extension BoundingBox {
    /// Whether this box holds the whole of another one. Touching edges count as inside.
    ///
    /// Boxes that cross the antimeridian are not supported (see ``BoundingBox``).
    ///
    /// - Parameter other: The box that has to lie inside this one.
    public func encloses(_ other: BoundingBox) -> Bool {
        south <= other.south && north >= other.north && west <= other.west && east >= other.east
    }

    /// Whether the two boxes overlap at all. Touching edges count as overlapping.
    ///
    /// - Parameter other: The other box.
    public func intersects(_ other: BoundingBox) -> Bool {
        south <= other.north && other.south <= north && west <= other.east && other.west <= east
    }
}
