/// Shorthand used by the built-in styles.
extension ZoomValue where Value == MapColor {
    /// A colour that is the same at every zoom level.
    static func color(_ hex: UInt32, alpha: Double = 1) -> ZoomValue<MapColor> {
        ZoomValue(constant: MapColor(hex: hex, alpha: alpha))
    }
}

extension ZoomValue where Value == Double {
    /// A number that is the same at every zoom level.
    static func constant(_ value: Double) -> ZoomValue<Double> {
        ZoomValue(constant: value)
    }
}

extension StrokeStyle {
    /// A solid screen-width line with a fixed colour.
    static func line(_ hex: UInt32, _ width: ZoomValue<Double>, dash: [Double] = [], casing: Casing? = nil) -> StrokeStyle {
        StrokeStyle(color: .color(hex), width: LineWidth(points: width), dash: dash, casing: casing)
    }
}
