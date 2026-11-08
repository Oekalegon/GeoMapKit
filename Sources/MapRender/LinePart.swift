/// One name to write along a line, measured, with the side of the line it goes on.
struct LinePart {
    /// Where the name goes in relation to the line.
    enum Side: Equatable {
        /// On the line.
        case on
        /// Above the line, in the direction the text reads.
        case above
        /// On the left of the line, looking in the direction in which its points are given.
        case left
        /// On the right of the line, looking in the direction in which its points are given.
        case right
    }

    var text: String
    var characters: [Character]
    /// Where each character starts along the text, plus the total as the last value.
    var starts: [Double]
    var size: (width: Double, height: Double)
    var side: Side
}
