import CoreGraphics
import Foundation
import ImageIO
import MapStyle

extension CoreGraphicsRenderer {
    /// Draws a scene into a bitmap.
    ///
    /// The image is `width × scale` by `height × scale` pixels in sRGB. It is the building block of ``pngData(for:style:scale:)``
    /// and of views that show a cached map image.
    ///
    /// - Parameters:
    ///   - scene: The scene to draw.
    ///   - style: The style the scene was built with.
    ///   - scale: Pixels per point (2 for a typical retina image). Must be at least 1 and at most 8.
    /// - Returns: The image.
    /// - Throws: ``MapRenderError/imageCreationFailed`` if the view has no area, the scale is out of range, or the
    ///   bitmap could not be created.
    public func cgImage(for scene: MapScene, style: MapStyle, scale: Double = 2) throws -> CGImage {
        // Validate before converting: a NaN or huge product cannot become an Int.
        guard (1.0...8.0).contains(scale), scene.viewport.width * scale <= 16_384, scene.viewport.height * scale <= 16_384
        else { throw MapRenderError.imageCreationFailed }
        let width = Int((scene.viewport.width * scale).rounded())
        let height = Int((scene.viewport.height * scale).rounded())
        guard width > 0, height > 0, width <= 16_384, height <= 16_384,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw MapRenderError.imageCreationFailed }
        // Flip to a top-left origin and work in points.
        context.translateBy(x: 0, y: Double(height))
        context.scaleBy(x: scale, y: -scale)
        draw(scene, style: style, into: context)
        guard let image = context.makeImage() else { throw MapRenderError.imageCreationFailed }
        return image
    }

    /// Draws a scene into a bitmap and encodes it as PNG.
    ///
    /// - Parameters:
    ///   - scene: The scene to draw.
    ///   - style: The style the scene was built with.
    ///   - scale: Pixels per point (2 for a typical retina image). Must be at least 1 and at most 8.
    /// - Returns: The PNG data.
    /// - Throws: ``MapRenderError/imageCreationFailed`` if the view has no area, the scale is out of range, or the
    ///   bitmap could not be created or encoded.
    public func pngData(for scene: MapScene, style: MapStyle, scale: Double = 2) throws -> Data {
        let image = try cgImage(for: scene, style: style, scale: scale)
        guard let data = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
        else { throw MapRenderError.imageCreationFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw MapRenderError.imageCreationFailed }
        return data as Data
    }
}
