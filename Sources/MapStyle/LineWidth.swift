/// The width of a stroked line: a screen width that depends on zoom, optionally widened to the real road width.
///
/// ``points`` is the width that keeps the line legible; it is also the minimum.
/// When ``ground`` is set and the map is zoomed in far enough that the real width is
/// larger than ``points``, the line takes the real width, so a motorway with four
/// lanes is visibly wider than a lane-wide service road.
public struct LineWidth: Sendable, Equatable {
    /// The legible (minimum) width in points, by zoom.
    public var points: ZoomValue<Double>
    /// The real-width rule, or `nil` for a line that keeps its screen width at every zoom.
    public var ground: GroundWidth?

    /// Creates a line width.
    public init(points: ZoomValue<Double>, ground: GroundWidth? = nil) {
        self.points = points
        self.ground = ground
    }

    /// The width to draw, in points.
    ///
    /// - Parameters:
    ///   - zoom: The (fractional) zoom level.
    ///   - metresPerPoint: The ground distance covered by one point at the current zoom and latitude.
    ///   - lanes: The feature's `lanes` tag as an integer, or `nil` if it has none or it does not parse.
    public func resolved(atZoom zoom: Double, metresPerPoint: Double, lanes: Int?) -> Double {
        let minimum = points.value(atZoom: zoom)
        guard let ground, metresPerPoint > 0, metresPerPoint.isFinite else { return minimum }
        return max(minimum, ground.metres(lanes: lanes) / metresPerPoint)
    }
}
