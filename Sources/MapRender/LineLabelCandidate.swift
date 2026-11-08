import MapStyle

/// A name that wants a place along a line, before collision handling.
///
/// The text is laid out along the line, letter by letter, where the line is straight enough. A long line can carry the name
/// more than once.
public struct LineLabelCandidate: Sendable, Equatable {
    /// The OSM ID of the way, to order candidates deterministically.
    public var objectID: Int64
    /// The text.
    public var text: String
    /// The vertices of the line in screen points, in the direction of the original line.
    public var points: [ScreenPoint]
    /// The font size in points at the current zoom.
    public var fontSize: Double
    /// The label style (colours, halo, priority).
    public var style: LabelStyle

    /// Creates a candidate.
    public init(objectID: Int64, text: String, points: [ScreenPoint], fontSize: Double, style: LabelStyle) {
        self.objectID = objectID
        self.text = text
        self.points = points
        self.fontSize = fontSize
        self.style = style
    }
}
