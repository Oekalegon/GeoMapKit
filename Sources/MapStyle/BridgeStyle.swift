/// How a class draws its bridges.
///
/// A bridge is drawn after all lines on the ground, with this casing instead of the class's own: a solid band around
/// the line that sets the deck apart from what it crosses. A class without a `BridgeStyle` draws its bridges like any
/// other line.
public struct BridgeStyle: Sendable, Equatable {
    /// The band around a bridge: colour and extra width on each side, by zoom.
    public var casing: StrokeStyle.Casing

    /// Creates a bridge style.
    public init(casing: StrokeStyle.Casing) {
        self.casing = casing
    }
}
