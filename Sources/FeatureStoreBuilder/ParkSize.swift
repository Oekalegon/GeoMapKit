import FeatureStore

/// Which protected areas have their border in the overview band (rule table version 21).
///
/// The border of every nature reserve and every Natura 2000 site is a dashed green line; in a country with many small ones (the
/// Veluwe, the dunes) they cover the map at zoom 9. A park whose outline is closed and encloses less than `minimumArea` is stored from
/// the mid band; one whose outline is not closed (so its size is not known) stays in the overview band.
enum ParkSize {
    /// 30 square kilometres: about 25 pixels across at zoom 9 at 52° N.
    static let minimumArea = 30_000_000.0

    static func isSmall(_ lines: [[PackedPoint]]) -> Bool {
        let closed = lines.filter { $0.count >= 4 && $0.first == $0.last }
        guard !closed.isEmpty else { return false }
        return WaterSize.measure(closed).area < minimumArea
    }
}
