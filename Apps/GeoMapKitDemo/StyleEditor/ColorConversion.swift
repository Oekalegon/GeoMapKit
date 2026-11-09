import MapStyle
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Between the colours of a style and the colours of SwiftUI (the colour picker).
enum ColorConversion {
    static func color(_ color: MapColor) -> Color {
        Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }

    /// The style colour for a picked colour, in sRGB, with each part rounded to a step of 1/255 (what a hex colour in a style file holds,
    /// so that the colour that was picked is the colour that is saved and read again).
    static func mapColor(_ color: Color) -> MapColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        #if canImport(UIKit)
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #else
        (NSColor(color).usingColorSpace(.sRGB) ?? .black).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif
        func step(_ value: CGFloat) -> Double { (Double(value) * 255).rounded() / 255 }
        return MapColor(red: step(red), green: step(green), blue: step(blue), alpha: step(alpha))
    }

    /// `#RRGGBB`, or `#RRGGBBAA` when the colour is not opaque, for showing.
    static func hex(_ color: MapColor) -> String {
        func part(_ value: Double) -> String { String(format: "%02X", Int((value * 255).rounded())) }
        let rgb = "#" + part(color.red) + part(color.green) + part(color.blue)
        return color.alpha < 1 ? rgb + part(color.alpha) : rgb
    }
}
