import FeatureStore
import Foundation

/// Which water areas are big enough for the overview band (rule table version 21).
///
/// The overview band is read from zoom 8 to 11. A polder is cut by thousands of ditches and canals that are mapped as areas, a few
/// metres wide and kilometres long, and drawn at those zooms they colour the land blue. An area whose mean width is under
/// `minimumWidth` or whose size is under `minimumArea` is therefore stored from the mid band (zoom 12) only; so is its outline.
enum WaterSize {
    /// The smallest mean width (2 × area ÷ perimeter) in metres: under it an area is a ditch or a canal, a line and not a surface.
    static let minimumWidth = 50.0
    /// The smallest size in square metres: 20 hectares, a bit under 7 pixels square at zoom 11 at 60° N.
    static let minimumArea = 200_000.0

    /// The area (square metres, every ring with its absolute area) and the perimeter (metres) of closed rings.
    static func measure(_ rings: [[PackedPoint]]) -> (area: Double, perimeter: Double) {
        var area = 0.0, perimeter = 0.0
        for ring in rings where ring.count >= 4 {
            let metresPerDegreeLongitude = 111_320.0 * cos(Double(ring[0].latitude) / 1e7 * .pi / 180)
            let metresPerDegreeLatitude = 110_574.0
            var twiceArea = 0.0
            for index in 0..<(ring.count - 1) {
                let ax = Double(ring[index].longitude) / 1e7 * metresPerDegreeLongitude
                let ay = Double(ring[index].latitude) / 1e7 * metresPerDegreeLatitude
                let bx = Double(ring[index + 1].longitude) / 1e7 * metresPerDegreeLongitude
                let by = Double(ring[index + 1].latitude) / 1e7 * metresPerDegreeLatitude
                twiceArea += ax * by - bx * ay
                perimeter += hypot(bx - ax, by - ay)
            }
            area += abs(twiceArea) / 2
        }
        return (area, perimeter)
    }

    /// Whether the rings (outer rings and holes together, each counted with its absolute area) are too thin or too small for the overview band.
    static func isSmall(_ rings: [[PackedPoint]]) -> Bool {
        let (area, perimeter) = measure(rings)
        guard perimeter > 0 else { return true }
        return area < minimumArea || 2 * area / perimeter < minimumWidth
    }

    /// The classification with its band raised to mid when the area is small and was in the overview band.
    static func adjusted(_ classification: Classification, rings: [[PackedPoint]]) -> Classification {
        guard classification.featureClass == .waterArea, classification.kind == .area, classification.minimumBand == .overview,
            isSmall(rings)
        else { return classification }
        return Classification(
            featureClass: classification.featureClass, subclass: classification.subclass, kind: classification.kind, minimumBand: .mid,
            showsOnWatch: classification.showsOnWatch)
    }
}

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
