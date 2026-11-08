import GeoCore
import MapRender

/// How a scroll wheel or a two-finger scroll moves the map: the arithmetic apart from the events, so it can be tested.
enum MapScroll {
    /// The zoom levels gained per unit of wheel delta (one notch of a mouse wheel is about one unit, more when it spins fast).
    static let zoomPerUnit = 0.1

    /// The viewport after a wheel turn: zoomed in or out so that the coordinate under the pointer stays under the pointer.
    ///
    /// - Parameters:
    ///   - viewport: The viewport before.
    ///   - pointer: The pointer position in the view, in points from the top-left corner.
    ///   - delta: The wheel delta; positive zooms in.
    ///   - range: The zoom range the result is held to.
    /// - Returns: The new centre and zoom.
    static func zoomed(
        _ viewport: MapViewport, at pointer: ScreenPoint, delta: Double, in range: ClosedRange<Double>
    ) -> (center: Coordinate, zoom: Double) {
        let zoom = min(max(viewport.zoom + delta * zoomPerUnit, range.lowerBound), range.upperBound)
        guard zoom != viewport.zoom else { return (viewport.center, viewport.zoom) }
        let anchor = viewport.coordinate(at: pointer)
        let scaled = MapViewport(center: viewport.center, zoom: zoom, width: viewport.width, height: viewport.height)
        let moved = scaled.screenPoint(for: anchor)
        let center = scaled.coordinate(
            at: ScreenPoint(x: viewport.width / 2 + moved.x - pointer.x, y: viewport.height / 2 + moved.y - pointer.y))
        return (center, zoom)
    }

    /// The centre after a two-finger scroll: the map follows the fingers.
    ///
    /// - Parameters:
    ///   - viewport: The viewport before.
    ///   - dx: The horizontal scroll, in points; positive moves the content to the right.
    ///   - dy: The vertical scroll, in points; positive moves the content down.
    static func panned(_ viewport: MapViewport, dx: Double, dy: Double) -> Coordinate {
        viewport.coordinate(at: ScreenPoint(x: viewport.width / 2 - dx, y: viewport.height / 2 - dy))
    }
}
