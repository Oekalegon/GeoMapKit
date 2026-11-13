import GeoCore

/// How far a built file falls short of the box it was asked to cover, per side.
///
/// The builder writes only cells that lie completely inside the box, so a box edge that cuts through a cell drops
/// that whole cell and the stored extent comes out smaller than the box. The gaps are in degrees and never negative.
public struct ExtentShortfall: Sendable, Equatable {
    /// Degrees the stored extent starts north of the box's south edge.
    public let south: Double
    /// Degrees the stored extent starts east of the box's west edge.
    public let west: Double
    /// Degrees the stored extent ends south of the box's north edge.
    public let north: Double
    /// Degrees the stored extent ends west of the box's east edge.
    public let east: Double

    /// Gaps below this many degrees (about a centimetre) are rounding, not a missing cell.
    static let tolerance = 1e-7

    /// The one-cell width in degrees of longitude at the storage zoom (13), a sensible amount to widen a box by.
    public static let oneCellInDegrees = 360.0 / 8_192

    /// Compares the stored extent with the requested area.
    ///
    /// - Parameters:
    ///   - requested: The box the user asked for.
    ///   - stored: The extent of the cells that were written.
    public init(requested: BoundingBox, stored: BoundingBox) {
        func gap(_ value: Double) -> Double { value > Self.tolerance ? value : 0 }
        south = gap(stored.south - requested.south)
        west = gap(stored.west - requested.west)
        north = gap(requested.north - stored.north)
        east = gap(requested.east - stored.east)
    }

    /// Whether the file covers the whole box.
    public var isEmpty: Bool { south == 0 && west == 0 && north == 0 && east == 0 }
}
