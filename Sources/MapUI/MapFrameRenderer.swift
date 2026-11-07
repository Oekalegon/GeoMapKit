import CoreGraphics
import FeatureStore
import MapRender
import MapStyle

/// Turns a viewport into a ``MapFrame`` off the main thread.
///
/// It is a plain value: the store file is memory-mapped and read-only, so each call builds its own scene without
/// shared state, and two calls can run at once.
struct MapFrameRenderer: Sendable {
    /// The store to read.
    let file: FeatureStoreFile
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
        let scene = try MapSceneBuilder(file: file, style: style).scene(for: viewport)
        let image = try CoreGraphicsRenderer().cgImage(for: scene, style: style, scale: scale)
        return MapFrame(image: image, viewport: viewport, scale: scale, styleID: styleID)
    }
}
