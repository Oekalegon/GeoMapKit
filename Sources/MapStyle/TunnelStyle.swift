/// How a class draws its tunnels.
///
/// A tunnel is drawn before the lines on the ground, so what runs over it stays on top, and fainter: the class's
/// line with its opacity multiplied by ``opacity``, no casing, and the dash pattern ``dash`` if it is not empty. A
/// class without a `TunnelStyle` draws its tunnels like any other line.
public struct TunnelStyle: Sendable, Equatable {
    /// A factor from 0 to 1 for the opacity of the line.
    public var opacity: Double
    /// The dash pattern in points (on, off, on, off ...), or empty to keep the class's own.
    public var dash: [Double]

    /// Creates a tunnel style; the opacity is clamped to 0 through 1.
    public init(opacity: Double = 0.5, dash: [Double] = []) {
        self.opacity = min(max(opacity.isFinite ? opacity : 0.5, 0), 1)
        self.dash = dash
    }
}
