import FeatureStore
import MapRender
import MapStyle
import Observation

/// Keeps the cached ``MapFrame`` of a ``MapView`` and decides when to draw a new one.
///
/// Drawing happens only on events: the requested viewport changed enough (see ``MapFramePlan``), the style or the
/// store changed, or a gesture ended. There are no timers. One frame is drawn at a time; a request that arrives
/// while a frame is being drawn replaces the waiting one, so the work never queues up.
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
    private var waiting: (viewport: MapViewport, scale: Double)?

    /// Creates a model.
    init(file: FeatureStoreFile, style: MapStyle) {
        renderer = MapFrameRenderer(file: file, style: style, styleID: 0)
    }

    /// Replaces the store or the style, dropping the cached frame if it no longer matches.
    func update(file: FeatureStoreFile, style: MapStyle) {
        generation += 1
        renderer = MapFrameRenderer(file: file, style: style, styleID: generation)
        frame = nil
    }

    /// Tells the model what should be on screen.
    ///
    /// - Parameters:
    ///   - viewport: The view's viewport (no margin).
    ///   - scale: The display scale.
    ///   - interacting: Whether a gesture is in progress.
    func request(viewport: MapViewport, scale: Double, interacting: Bool) {
        guard viewport.width > 0, viewport.height > 0 else { return }
        if let frame, frame.styleID == renderer.styleID {
            let plan = MapFramePlan(frame: frame.viewport, requested: viewport)
            guard plan.needsNewFrame(interacting: interacting) else { return }
        }
        let margin = MapFramePlan.margin(forViewWidth: viewport.width, viewHeight: viewport.height)
        let padded = MapViewport(
            center: viewport.center, zoom: viewport.zoom, width: viewport.width + 2 * margin, height: viewport.height + 2 * margin)
        draw(padded, scale: scale)
    }

    private func draw(_ viewport: MapViewport, scale: Double) {
        guard !drawing else {
            waiting = (viewport, scale)
            return
        }
        drawing = true
        let renderer = renderer
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try renderer.frame(for: viewport, scale: scale) }
            }.value
            drawing = false
            switch result {
            case .success(let drawn):
                // A frame for an old style or store is stale; the next request draws a new one.
                if drawn.styleID == self.renderer.styleID {
                    frame = drawn
                    errorDescription = nil
                }
            case .failure(let error):
                errorDescription = "\(error)"
            }
            if let next = waiting {
                waiting = nil
                draw(next.viewport, scale: next.scale)
            }
        }
    }
}
