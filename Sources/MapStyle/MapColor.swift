/// A colour in the sRGB colour space with an alpha channel.
///
/// `MapStyle` does not depend on SwiftUI or Core Graphics, so the style model
/// builds for every platform and in tests. The renderer converts it.
public struct MapColor: Sendable, Equatable, Hashable {
    /// Red, 0...1.
    public var red: Double
    /// Green, 0...1.
    public var green: Double
    /// Blue, 0...1.
    public var blue: Double
    /// Opacity, 0 (clear) to 1 (opaque).
    public var alpha: Double

    /// Creates a colour from components in 0...1. Values outside the range are clamped.
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    /// Creates a colour from a 24-bit `0xRRGGBB` value.
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, alpha: alpha)
    }

    /// Returns the same colour with a different opacity.
    public func withAlpha(_ alpha: Double) -> MapColor {
        MapColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Opaque white.
    public static let white = MapColor(red: 1, green: 1, blue: 1)
    /// Opaque black.
    public static let black = MapColor(red: 0, green: 0, blue: 0)
    /// Fully transparent.
    public static let clear = MapColor(red: 0, green: 0, blue: 0, alpha: 0)

    private static func clamp(_ value: Double) -> Double { value.isNaN ? 0 : min(max(value, 0), 1) }
}

extension MapColor: ZoomInterpolatable {
    public func interpolated(to other: MapColor, fraction: Double) -> MapColor {
        MapColor(
            red: red.interpolated(to: other.red, fraction: fraction),
            green: green.interpolated(to: other.green, fraction: fraction),
            blue: blue.interpolated(to: other.blue, fraction: fraction),
            alpha: alpha.interpolated(to: other.alpha, fraction: fraction))
    }
}
