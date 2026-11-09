import FeatureStore

/// What one coarse level of a set of blocks holds (question 50).
///
/// A level serves the zooms above `topZoom - 1` up to `topZoom`. Its cells have the storage zoom `topZoom + 2`, so a view
/// at those zooms touches about the same number of cells at every level, and it has one band, whose geometry is
/// simplified for the top of the range.
public struct LevelSpec: Sendable, Equatable {
    /// The highest zoom the level serves, 1 to 11.
    public let topZoom: Int
    /// The classes the level holds: the classes the style shows at the top zoom.
    public let classes: Set<UInt8>

    /// The zoom of the cells of the level, `topZoom + 2`.
    public var storageZoom: Int { topZoom + 2 }

    /// One pixel of a 256-pixel tile at the top zoom, in projected radians.
    var pixel: Double { 2 * .pi / (256 * Double(1 << topZoom)) }
    /// The Douglas–Peucker tolerance: half a pixel at the top zoom.
    var tolerance: Double { 0.5 * pixel }
    /// A feature whose bounding box is smaller than three pixels is left out.
    var minimumExtent: Double { 3 * pixel }

    /// - Parameters:
    ///   - topZoom: The highest zoom the level serves (1 to 11).
    ///   - classes: The raw class IDs the level holds.
    /// - Throws: ``LevelError/invalidTopZoom(_:)`` for a zoom outside 1 to 11.
    public init(topZoom: Int, classes: Set<UInt8>) throws {
        guard (1...11).contains(topZoom) else { throw LevelError.invalidTopZoom(topZoom) }
        self.topZoom = topZoom
        self.classes = classes
    }
}
