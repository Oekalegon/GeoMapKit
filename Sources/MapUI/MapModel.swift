import FeatureStore
import MapRender
import MapStyle
import Observation

/// Keeps the cached ``MapFrame`` of a ``MapView`` and decides when to draw a new one.
///
/// Drawing happens only on events: the requested viewport changed enough (see ``MapFramePlan``), the style or the
/// store changed, or a gesture ended. There are no timers. One frame is drawn at a time; requests that arrive
/// meanwhile only update the latest wanted viewport, which is checked when the frame arrives, so the work never
/// queues up and a frame that is already out of date is corrected once.
@MainActor
@Observable
final class MapModel {
    /// The frame to show, or `nil` before the first one is ready.
    private(set) var frame: MapFrame?
    /// The last error, shown instead of the map when there is no frame at all.
    private(set) var errorDescription: String?

    private var renderer: MapFrameRenderer
    /// Counts style and store changes; a frame from an older generation is stale.
    private var generation = 0
    private var drawing = false
    private var latest: (viewport: MapViewport, scale: Double, interacting: Bool)?

    /// Creates a model that draws a store: one file, or a set of block files.
    init(source: any CellSource, style: MapStyle) {
        renderer = MapFrameRenderer(source: source, style: style, styleID: 0)
    }

    /// Creates a model that draws one store file.
    convenience init(file: FeatureStoreFile, style: MapStyle) {
        self.init(source: file, style: style)
    }

    /// Replaces the store or the style, dropping the cached frame if it no longer matches.
    func update(source: any CellSource, style: MapStyle) {
        generation += 1
        renderer = MapFrameRenderer(source: source, style: style, styleID: generation)
        frame = nil
    }

    /// Replaces the store file or the style, dropping the cached frame if it no longer matches.
    func update(file: FeatureStoreFile, style: MapStyle) {
        update(source: file, style: style)
    }

    /// Tells the model what should be on screen.
    ///
    /// - Parameters:
    ///   - viewport: The view's viewport (no margin).
    ///   - scale: The display scale.
    ///   - interacting: Whether a gesture is in progress.
    func request(viewport: MapViewport, scale: Double, interacting: Bool) {
        guard viewport.width > 0, viewport.height > 0 else { return }
        latest = (viewport, scale, interacting)
        evaluate()
    }

    /// Draws a frame for the latest request if the cached one is not good enough and nothing is being drawn.
    ///
    /// It also runs when a frame arrives: the user may have moved on while it was drawn, and nothing else would
    /// ask for a correction once the gestures have ended.
    private func evaluate() {
        guard !drawing, let (viewport, scale, interacting) = latest else { return }
        if let frame, frame.styleID == renderer.styleID {
            let plan = MapFramePlan(frame: frame.viewport, requested: viewport)
            guard plan.needsNewFrame(interacting: interacting) else { return }
        }
        let margin = MapFramePlan.margin(forViewWidth: viewport.width, viewHeight: viewport.height)
        let padded = MapViewport(
            center: viewport.center, zoom: viewport.zoom, width: viewport.width + 2 * margin, height: viewport.height + 2 * margin,
            bearing: viewport.bearing, labelInset: margin)
        draw(padded, scale: scale)
    }

    private func draw(_ viewport: MapViewport, scale: Double) {
        drawing = true
        let renderer = renderer
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try renderer.frame(for: viewport, scale: scale) }
            }.value
            drawing = false
            switch result {
            case .success(let drawn):
                // A frame for an old style or store is stale and is never shown.
                if drawn.styleID == self.renderer.styleID {
                    frame = drawn
                    errorDescription = nil
                }
                evaluate()
            case .failure(let error):
                // No retry: the same request would fail again. The next event asks again.
                errorDescription = "\(error)"
            }
        }
    }
}
