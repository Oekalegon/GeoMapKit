/// One letter of a label that runs along a line.
public struct PlacedGlyph: Sendable, Equatable {
    /// The character (a grapheme cluster, so a letter with its accents stays one glyph).
    public var text: String
    /// The middle of the letter's advance, on the line the text follows, in screen points.
    public var position: ScreenPoint
    /// The direction of the text at the letter, in radians, in screen coordinates (y grows downwards): 0 reads to the right
    /// and a positive angle turns clockwise. It is always within a quarter turn of horizontal, so text is never upside down.
    public var angle: Double
    /// The advance of the letter in points.
    public var width: Double

    /// Creates a glyph.
    public init(text: String, position: ScreenPoint, angle: Double, width: Double) {
        self.text = text
        self.position = position
        self.angle = angle
        self.width = width
    }
}
