import Foundation
import GeoCore
import MapRender

/// A scale bar for a map: how long it is on the screen, and what distance it stands for.
///
/// The distance is a round number (1, 2 or 5 times a power of ten; in miles also a quarter and a half), the largest that makes a bar of
/// at most the maximum width. The ground distance per point is that of Web Mercator at the latitude of the ruler, with
/// ``Coordinate/earthRadius``: the map is isotropic, so a turned map has the same scale in every direction.
public struct ScaleRuler: Sendable, Equatable {
    /// The length of the bar in points.
    public let length: Double
    /// The distance the bar stands for, in the unit of ``label`` (metres, kilometres, feet or miles).
    public let distance: Double
    /// The text, for example "200 m", "5 km", "500 ft" or "0.5 mi".
    public let label: String

    /// The ground distance of one point, in metres, at a latitude and zoom level (256-point tiles).
    ///
    /// - Parameters:
    ///   - latitude: In degrees; it is limited to the Web Mercator range.
    ///   - zoom: The fractional zoom level.
    public static func metresPerPoint(latitude: Double, zoom: Double) -> Double {
        let limit = TileID.maximumLatitude
        let clamped = min(max(latitude.isFinite ? latitude : 0, -limit), limit)
        return 2 * .pi * Coordinate.earthRadius * cos(clamped * .pi / 180) / (MapViewport.tileSize * pow(2, zoom))
    }

    /// The ruler for a latitude and zoom level.
    ///
    /// - Parameters:
    ///   - latitude: The latitude of the ruler, in degrees.
    ///   - zoom: The fractional zoom level.
    ///   - maximumWidth: The longest the bar may be, in points.
    ///   - units: The units of the label.
    /// - Returns: The ruler, or `nil` when even the shortest distance (1 m or 1 ft) would be wider than the maximum, or the numbers are not
    ///   finite.
    public static func make(latitude: Double, zoom: Double, maximumWidth: Double, units: ScaleRulerUnits) -> ScaleRuler? {
        let perPoint = metresPerPoint(latitude: latitude, zoom: zoom)
        guard perPoint.isFinite, perPoint > 0, maximumWidth.isFinite, maximumWidth > 0 else { return nil }
        let available = perPoint * maximumWidth
        switch units {
        case .metric:
            guard let metres = roundNumber(atMost: available, steps: [1, 2, 5], from: 1) else { return nil }
            let label = metres >= 1_000 ? "\(format(metres / 1_000)) km" : "\(format(metres)) m"
            return ScaleRuler(length: metres / perPoint, distance: metres >= 1_000 ? metres / 1_000 : metres, label: label)
        case .imperial:
            let feetPerMetre = 1 / 0.3048
            let feet = available * feetPerMetre
            // Feet up to a quarter of a mile, miles above.
            if feet < 1_320 {
                guard let value = roundNumber(atMost: feet, steps: [1, 2, 5], from: 1) else { return nil }
                return ScaleRuler(length: value / feetPerMetre / perPoint, distance: value, label: "\(format(value)) ft")
            }
            let miles = feet / 5_280
            guard let value = roundNumber(atMost: miles, steps: [1, 2, 5], from: 1, extra: [0.25, 0.5]) else { return nil }
            return ScaleRuler(length: value * 5_280 / feetPerMetre / perPoint, distance: value, label: "\(format(value)) mi")
        }
    }

    /// The ruler of the view of a map, at the latitude of its lower edge (where the ruler is drawn).
    ///
    /// - Parameters:
    ///   - viewport: The view.
    ///   - maximumWidth: The longest the bar may be, in points.
    ///   - units: The units of the label.
    /// - Returns: See ``make(latitude:zoom:maximumWidth:units:)``.
    public static func make(in viewport: MapViewport, maximumWidth: Double, units: ScaleRulerUnits) -> ScaleRuler? {
        let bottom = viewport.coordinate(at: ScreenPoint(x: viewport.width / 2, y: viewport.height))
        return make(latitude: bottom.latitude, zoom: viewport.zoom, maximumWidth: maximumWidth, units: units)
    }

    /// The largest of 1, 2 and 5 times a power of ten, with the extra values, that is at most `limit`; nil when `limit` is below `from`.
    private static func roundNumber(atMost limit: Double, steps: [Double], from first: Double, extra: [Double] = []) -> Double? {
        guard limit >= min(first, extra.min() ?? first) else { return nil }
        var best: Double?
        var power = first
        while power <= limit * 10 {
            for step in steps where step * power <= limit { best = max(best ?? 0, step * power) }
            power *= 10
        }
        for value in extra where value <= limit { best = max(best ?? 0, value) }
        return best
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
