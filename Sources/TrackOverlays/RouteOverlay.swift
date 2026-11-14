import Foundation
import GeoCore
import MapRender
import MapStyle
import Synchronization
import Tracks

/// Draws a ``Route`` over the map: the line, a marker at the start and at the end, and the waypoints.
///
/// The line is cut at the breaks of a recording (``Route/segmentStarts``), so a pause is not drawn as a straight line. A route of many
/// thousands of points is simplified to the zoom before it is projected (to within about half a screen point, kept for each zoom level),
/// and the parts outside the frame are clipped away, so a frame costs about the same for a long route as for a short one.
///
/// The overlay is immutable and has one id for its life.
public final class RouteOverlay: MapOverlay, Sendable {
    public let overlayID = UUID()
    /// The route that is drawn.
    public let route: Route
    /// How it looks.
    public let style: RouteOverlayStyle

    /// The points to keep for each segment of the route, by zoom level, for the levels drawn last (see ``cachedLevels``). A level is
    /// computed when it is first drawn; it holds up to one index for each point of the route, so the number kept is bounded.
    private let simplified = Mutex<(order: [Int], levels: [Int: [[Int]]])>(([], [:]))

    /// How many zoom levels are kept: the one in use and the two before it, which is what zooming in and out across a level border needs.
    static let cachedLevels = 3

    /// How many zoom levels are held now (for tests).
    var heldLevelCount: Int { simplified.withLock { $0.levels.count } }

    /// The most a simplified line may differ from the route, in screen points at the level's zoom (so up to twice that at the
    /// highest zoom of the level).
    static let tolerance = 0.35

    /// Creates the overlay.
    ///
    /// - Parameters:
    ///   - route: The route.
    ///   - style: How it looks.
    public init(route: Route, style: RouteOverlayStyle = .standard) {
        self.route = route
        self.style = style
    }

    public func items(for viewport: MapViewport) -> [OverlayItem] {
        // What is kept outside the view: the width of the line, the casing and the markers.
        let pad = style.line.width + 2 * (style.line.casing?.extraPoints ?? 0) + 2 * style.endRadius + 4
        let area = PolylineClipper.Rectangle(minX: -pad, minY: -pad, maxX: viewport.width + pad, maxY: viewport.height + pad)
        var items: [OverlayItem] = []
        if route.points.count >= 2 {
            for indices in segmentIndices(forZoom: viewport.zoom) where indices.count >= 2 {
                let screen = indices.map { viewport.screenPoint(for: route.points[$0].coordinate) }
                for part in PolylineClipper.clip(screen, to: area) {
                    items.append(.line(OverlayLine(points: part, style: style.line)))
                }
            }
        }
        func inside(_ point: ScreenPoint) -> Bool { point.x >= area.minX && point.x <= area.maxX && point.y >= area.minY && point.y <= area.maxY }
        for waypoint in route.waypoints {
            let point = viewport.screenPoint(for: waypoint.coordinate)
            guard inside(point) else { continue }
            items.append(.marker(OverlayMarker(
                center: point, radius: style.waypointRadius, fill: style.waypoint, outline: style.waypointOutline,
                outlineWidth: waypoint.isRequired ? style.requiredRing : 1)))
        }
        if let first = route.points.first?.coordinate, let last = route.points.last?.coordinate {
            let end = viewport.screenPoint(for: last)
            if inside(end) { items.append(.marker(OverlayMarker(center: end, radius: style.endRadius, fill: style.end, outline: .init(hex: 0xFFFFFF), outlineWidth: 1.5))) }
            let start = viewport.screenPoint(for: first)
            if inside(start) { items.append(.marker(OverlayMarker(center: start, radius: style.endRadius, fill: style.start, outline: .init(hex: 0xFFFFFF), outlineWidth: 1.5))) }
        }
        return items
    }

    /// The indices to draw for each segment at a zoom, from the cache or computed.
    private func segmentIndices(forZoom zoom: Double) -> [[Int]] {
        let level = min(max(Int(zoom.rounded(.down)), 0), 24)
        let found: [[Int]]? = simplified.withLock { cache in
            guard let cached = cache.levels[level] else { return nil }
            // The level in use is the newest.
            cache.order.removeAll { $0 == level }
            cache.order.append(level)
            return cached
        }
        if let found { return found }
        let world = 256 * exp2(Double(level))
        // The points in the flat plane of the level (Web Mercator, in points of that zoom), like the viewport's own projection.
        var x = [Double](), y = [Double]()
        x.reserveCapacity(route.points.count)
        y.reserveCapacity(route.points.count)
        for point in route.points {
            let latitude = min(max(point.coordinate.latitude, -TileID.maximumLatitude), TileID.maximumLatitude)
            x.append((point.coordinate.longitude + 180) / 360 * world)
            y.append((1 - asinh(tan(latitude * .pi / 180)) / .pi) / 2 * world)
        }
        var starts = route.segmentStarts
        starts.append(route.points.count)
        // The step between two segments is not drawn, but each segment ends where the next begins in the route's distances; the line
        // of a segment is its own points only.
        let result = (0..<(starts.count - 1)).map { index in
            RouteSimplifier.keep(x: x, y: y, in: starts[index]..<starts[index + 1], tolerance: Self.tolerance)
        }
        simplified.withLock { cache in
            cache.levels[level] = result
            cache.order.removeAll { $0 == level }
            cache.order.append(level)
            while cache.order.count > Self.cachedLevels { cache.levels[cache.order.removeFirst()] = nil }
        }
        return result
    }
}
