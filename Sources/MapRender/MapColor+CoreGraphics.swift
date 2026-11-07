import CoreGraphics
import MapStyle

extension MapColor {
    /// The colour as a `CGColor` in the sRGB colour space.
    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
