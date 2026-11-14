import Foundation

/// Something drawn over the map that is not part of the map data: a route, a track, a set of markers.
///
/// An overlay turns a viewport into items in screen points (``OverlayItem``), the same coordinates the scene uses, so a backend only
/// has to draw them and the overlay knows nothing about graphics. The renderer draws the items of all overlays after the map
/// features and before the labels: a route lies over the roads and under the place names.
///
/// The items are part of the cached map image, so an overlay is for what changes rarely (a route to follow, tracks the user chose to
/// show). What changes with every position fix (the position itself, a track being recorded) belongs in a layer drawn above the
/// image, which the map view does not have yet.
///
/// `items(for:)` is called off the main thread, from the task that draws a frame, and may be called from two tasks at once.
public protocol MapOverlay: Sendable {
    /// Identifies what the overlay draws. The view draws a new image when the list of ids changes, so an overlay whose content
    /// changes must give a new id (an immutable overlay can keep one for its life).
    var overlayID: UUID { get }

    /// The items to draw for a viewport.
    ///
    /// The viewport is the frame's: the view plus a margin on every side. Items outside it are clipped by the renderer, but an overlay
    /// should not make items it knows are far outside (a route of 100,000 points should cost about as much at every zoom).
    ///
    /// - Parameter viewport: What is drawn.
    /// - Returns: The items, in drawing order.
    func items(for viewport: MapViewport) -> [OverlayItem]
}
