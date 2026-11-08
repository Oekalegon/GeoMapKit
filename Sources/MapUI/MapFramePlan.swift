import Foundation
import MapRender

/// Where and how large a cached ``MapFrame`` appears in the view, and whether it must be drawn again.
///
/// This is the whole "redraw only when needed" rule in one pure value, so it can be tested without a view:
/// the frame is moved, scaled and turned to follow the requested viewport, and a new frame is only needed when the old one
/// no longer covers the view or was drawn at a different zoom or bearing.
struct MapFramePlan: Equatable {
    /// The screen position of the frame's centre, in points of the requested viewport.
    var centre: ScreenPoint
    /// The size the frame is shown at, in points.
    var width: Double
    /// The size the frame is shown at, in points.
    var height: Double
    /// How far the image is turned clockwise when it is shown, in degrees from -180 to 180: the bearing it was drawn with
    /// minus the one requested. The image turns about its own centre.
    var rotation: Double
    /// Whether the shown frame covers the whole view.
    var coversView: Bool
    /// Whether the frame was drawn at a different zoom than the one requested.
    var zoomDiffers: Bool
    /// Whether the frame was drawn with a bearing that differs from the requested one by more than ``bearingTolerance``.
    var bearingDiffers: Bool
    /// How far the frame's centre is from the view's centre, in points (the larger of the two axes).
    var drift: Double
    /// The drift above which a new frame is drawn once the gesture has ended, so there is room for the next pan.
    var driftLimit: Double

    /// Zoom differences below this are drawn as is (about a thousandth of a pixel at 256 points).
    static let zoomTolerance = 1e-6

    /// Bearing differences below this, in degrees, are drawn as is: the labels are that much off the upright, which cannot
    /// be seen. It also keeps a compass heading that jitters by a degree from drawing a frame each time.
    static let bearingTolerance = 1.0

    /// The most the frame extends past the view on each side, in points. It bounds the size of the image: on a large
    /// iPad view, half a screen of margin would make an image of more than 100 MB.
    static let maximumMargin = 256.0

    /// The extra area drawn around the view on every side, in points: half the larger dimension of the view, but
    /// not more than ``maximumMargin``.
    ///
    /// With this margin a pan of up to half a screen (on a Watch or iPhone) is shown without drawing again. It also covers
    /// a turn of any angle: the frame must contain the circle around the view, which needs a margin of the half diagonal
    /// minus the half of the shorter side, and that is never more than half the larger side. Where the cap applies (a large
    /// view) a big turn can uncover the view, and a new frame is drawn before the gesture ends.
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
        var turn = (frame.bearing - requested.bearing).truncatingRemainder(dividingBy: 360)
        if turn > 180 { turn -= 360 } else if turn < -180 { turn += 360 }
        rotation = turn
        bearingDiffers = abs(turn) > Self.bearingTolerance
        drift = max(abs(centre.x - requested.width / 2), abs(centre.y - requested.height / 2))
        driftLimit = Self.margin(forViewWidth: requested.width, viewHeight: requested.height) / 2
        // Each corner of the view, seen from the frame's centre and turned back into the axes of the image, must lie on the image.
        let radians = turn * .pi / 180
        let cosine = turn == 0 ? 1 : cos(radians), sine = turn == 0 ? 0 : sin(radians)
        var covers = true
        for corner in [(0.0, 0.0), (requested.width, 0), (0, requested.height), (requested.width, requested.height)] {
            let dx = corner.0 - centre.x, dy = corner.1 - centre.y
            // The image is shown turned clockwise by `turn`; its own axes are the screen axes turned back, anticlockwise.
            let x = dx * cosine + dy * sine, y = -dx * sine + dy * cosine
            if abs(x) > width / 2 || abs(y) > height / 2 { covers = false }
        }
        coversView = covers
    }

    /// Whether a new frame is needed for the requested viewport.
    ///
    /// - Parameter interacting: Whether a gesture is in progress. While the user pans, a new frame is started as
    ///   soon as the view has drifted past ``driftLimit`` (half the margin), not only when the old frame stops covering
    ///   the view: drawing takes time, and the user keeps moving meanwhile, so waiting for the edge would show an empty
    ///   border at every cell. While the user pinches or rotates, the old frame is only scaled or turned; a change of zoom or
    ///   bearing is drawn when the gesture ends, unless the frame no longer covers the view.
    func needsNewFrame(interacting: Bool) -> Bool {
        if !coversView || drift > driftLimit { return true }
        return !interacting && (zoomDiffers || bearingDiffers)
    }
}
