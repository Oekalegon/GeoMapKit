import Foundation
import MapRender

/// Where and how large a cached ``MapFrame`` appears in the view, and whether it must be drawn again.
///
/// This is the whole "redraw only when needed" rule in one pure value, so it can be tested without a view:
/// the frame is moved and scaled to follow the requested viewport, and a new frame is only needed when the old one
/// no longer covers the view or was drawn at a different zoom.
struct MapFramePlan: Equatable {
    /// The screen position of the frame's centre, in points of the requested viewport.
    var centre: ScreenPoint
    /// The size the frame is shown at, in points.
    var width: Double
    /// The size the frame is shown at, in points.
    var height: Double
    /// Whether the shown frame covers the whole view.
    var coversView: Bool
    /// Whether the frame was drawn at a different zoom than the one requested.
    var zoomDiffers: Bool
    /// How far the frame's centre is from the view's centre, in points (the larger of the two axes).
    var drift: Double
    /// The drift above which a new frame is drawn once the gesture has ended, so there is room for the next pan.
    var driftLimit: Double

    /// Zoom differences below this are drawn as is (about a thousandth of a pixel at 256 points).
    static let zoomTolerance = 1e-6

    /// The most the frame extends past the view on each side, in points. It bounds the size of the image: on a large
    /// iPad view, half a screen of margin would make an image of more than 100 MB.
    static let maximumMargin = 256.0

    /// The extra area drawn around the view on every side, in points: half the larger dimension of the view, but
    /// not more than ``maximumMargin``.
    ///
    /// With this margin a pan of up to half a screen (on a Watch or iPhone) is shown without drawing again.
    static func margin(forViewWidth width: Double, viewHeight height: Double) -> Double {
        min((max(width, height) / 2).rounded(.up), maximumMargin)
    }

    /// Plans how to show `frame` in `requested`.
    ///
    /// - Parameters:
    ///   - frame: The viewport the cached image was drawn for.
    ///   - requested: The viewport that should be on screen now.
    init(frame: MapViewport, requested: MapViewport) {
        let ratio = exp2(requested.zoom - frame.zoom)
        width = frame.width * ratio
        height = frame.height * ratio
        // Where the frame's centre coordinate falls in the requested viewport.
        centre = requested.screenPoint(for: frame.center)
        zoomDiffers = abs(requested.zoom - frame.zoom) > Self.zoomTolerance
        drift = max(abs(centre.x - requested.width / 2), abs(centre.y - requested.height / 2))
        driftLimit = Self.margin(forViewWidth: requested.width, viewHeight: requested.height) / 2
        coversView =
            centre.x - width / 2 <= 0 && centre.y - height / 2 <= 0
            && centre.x + width / 2 >= requested.width && centre.y + height / 2 >= requested.height
    }

    /// Whether a new frame is needed for the requested viewport.
    ///
    /// - Parameter interacting: Whether a gesture is in progress. While the user pans, a new frame is started as
    ///   soon as the view has drifted past ``driftLimit`` (half the margin), not only when the old frame stops covering
    ///   the view: drawing takes time, and the user keeps moving meanwhile, so waiting for the edge would show an empty
    ///   border at every cell. While the user pinches, the old frame is only scaled; a zoom change is drawn when the
    ///   gesture ends, unless the frame no longer covers the view.
    func needsNewFrame(interacting: Bool) -> Bool {
        if !coversView || drift > driftLimit { return true }
        return !interacting && zoomDiffers
    }
}
