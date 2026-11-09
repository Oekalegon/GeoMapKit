import CoreGraphics
import FeatureStore
import MapRender
import MapStyle

/// Turns a viewport into a ``MapFrame`` off the main thread.
///
/// It is a plain value: the store file is memory-mapped and read-only, so each call builds its own scene without
/// shared state, and two calls can run at once.
struct MapFrameRenderer: Sendable {
    /// The store to read: one file, or a set of block files.
    let source: any CellSource
    /// The style to draw with.
    let style: MapStyle
    /// Identifies the style for ``MapFrame/styleID``.
    let styleID: Int

    /// Draws a frame.
    ///
    /// - Parameters:
    ///   - viewport: What the frame must show, margin included.
    ///   - scale: Pixels per point (the display scale, limited to 1...3 to keep the image small).
    /// - Throws: ``MapRenderError`` if no band can be read or the image cannot be created, and the store errors.
    func frame(for viewport: MapViewport, scale: Double) throws -> MapFrame {
        let scale = min(max(scale, 1), 3)
        let scene = try MapSceneBuilder(source: source, style: style).scene(for: viewport)
        // The credit is not part of the image: the image is larger than the view and turns, so its corner is not the view's.
        // `MapView` shows the credit itself, in the corner of the view.
        var drawn = style
        drawn.attribution = .hidden
        let image = try CoreGraphicsRenderer().cgImage(for: scene, style: drawn, scale: scale)
        return MapFrame(image: image, viewport: viewport, scale: scale, styleID: styleID)
    }
}
