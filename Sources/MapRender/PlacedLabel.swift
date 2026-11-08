import MapStyle

/// A label with its final place.
public struct PlacedLabel: Sendable, Equatable {
    /// The text.
    public var text: String
    /// The top-left corner of the text box in screen points.
    public var origin: ScreenPoint
    /// The width of the text box in points.
    public var width: Double
    /// The height of the text box in points.
    public var height: Double
    /// The font size in points.
    public var fontSize: Double
    /// The label style.
    public var style: LabelStyle
    /// For a label along a line: its letters, each with a position and a direction. Empty for a label drawn in one piece.
    /// Then `origin`, `width` and `height` are the box around the letters.
    public var glyphs: [PlacedGlyph]

    /// Creates a placed label.
    public init(
        text: String, origin: ScreenPoint, width: Double, height: Double, fontSize: Double, style: LabelStyle,
        glyphs: [PlacedGlyph] = []
    ) {
        self.text = text
        self.origin = origin
        self.width = width
        self.height = height
        self.fontSize = fontSize
        self.style = style
        self.glyphs = glyphs
    }
}
