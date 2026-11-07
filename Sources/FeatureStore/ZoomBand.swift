/// A group of zoom levels that share one baked copy of the geometry.
///
/// The detail band holds the original OSM geometry; the other bands hold
/// simplified copies. The Watch normally holds only ``mid`` and ``detail``.
public enum ZoomBand: UInt8, CaseIterable, Sendable, Comparable {
    /// Zoom 8 to 11 (provisional boundaries, see the architecture document).
    case overview = 0
    /// Zoom 12 to 14.
    case mid = 1
    /// Zoom 15 and up: the original geometry.
    case detail = 2

    public static func < (lhs: ZoomBand, rhs: ZoomBand) -> Bool { lhs.rawValue < rhs.rawValue }
}
