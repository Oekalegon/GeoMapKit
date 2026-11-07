import CoreGraphics
import MapRender

/// A rendered map image together with what it shows.
///
/// A frame covers more than the view (see `MapFramePlan.margin(forViewWidth:viewHeight:)`), so small pans and
/// zoom changes can be shown by moving and scaling the image instead of drawing again.
struct MapFrame: @unchecked Sendable {
    /// The image, `viewport.width × scale` by `viewport.height × scale` pixels.
    ///
    /// `CGImage` is immutable, which is why the frame can be shared across tasks.
    let image: CGImage
    /// The viewport the image was drawn for (the view plus the margin on every side).
    let viewport: MapViewport
    /// Pixels per point of the image.
    let scale: Double
    /// The style identity the frame was drawn with, so a style change invalidates it.
    let styleID: Int
}
