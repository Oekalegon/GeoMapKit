import MapRender
import MapStyle

/// How a ``RouteOverlay`` looks: a coloured line with a light edge, a green dot at the start, a red one at the end, and small circles
/// for the waypoints. All sizes are in screen points, so a route looks the same at every zoom.
public struct RouteOverlayStyle: Sendable, Equatable {
    /// The line of the route.
    public var line: OverlayLineStyle
    /// The marker at the start of the route.
    public var start: MapColor
    /// The marker at the end of the route.
    public var end: MapColor
    /// The radius of the start and end markers in points.
    public var endRadius: Double
    /// The fill of a waypoint.
    public var waypoint: MapColor
    /// The outline of a waypoint.
    public var waypointOutline: MapColor
    /// The radius of a waypoint in points; a required one is drawn with a ring of `requiredRing` points around it.
    public var waypointRadius: Double
    /// The width of the ring around a required waypoint, in points.
    public var requiredRing: Double

    /// Creates a style.
    public init(
        line: OverlayLineStyle, start: MapColor, end: MapColor, endRadius: Double, waypoint: MapColor, waypointOutline: MapColor,
        waypointRadius: Double, requiredRing: Double
    ) {
        self.line = line
        self.start = start
        self.end = end
        self.endRadius = endRadius
        self.waypoint = waypoint
        self.waypointOutline = waypointOutline
        self.waypointRadius = waypointRadius
        self.requiredRing = requiredRing
    }

    /// The look of the apps: a blue line of 5 points with a white edge, round ends, a green start and a red end.
    public static let standard = RouteOverlayStyle(
        line: OverlayLineStyle(
            color: MapColor(hex: 0x2F6FED), width: 5, casing: .init(color: MapColor(hex: 0xFFFFFF, alpha: 0.9), extraPoints: 1.5)),
        start: MapColor(hex: 0x2EA44F), end: MapColor(hex: 0xD73A49), endRadius: 6,
        waypoint: MapColor(hex: 0xFFFFFF), waypointOutline: MapColor(hex: 0x2F6FED), waypointRadius: 3.5, requiredRing: 2)
}
