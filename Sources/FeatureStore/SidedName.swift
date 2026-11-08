/// A name that stands for the two sides of a line: the regions a border separates.
///
/// A border way is stored with one name, `left` and `right` joined by a line feed, where left and right are those of the
/// way's own direction, the direction in which its points are stored. A map that writes the names along the border can
/// then put each name on the side of its region.
public struct SidedName: Sendable, Equatable {
    /// The character between the two names in the text form.
    public static let separator: Character = "\n"

    /// The name of the region on the left of the line, looking in the direction of its points. Empty if there is none.
    public var left: String
    /// The name of the region on the right of the line, looking in the direction of its points. Empty if there is none.
    public var right: String

    /// Creates a name from the two sides.
    public init(left: String, right: String) {
        self.left = left
        self.right = right
    }

    /// Reads the text form, or returns `nil` for a text that is not a name of two sides (it has no separator, or more
    /// than one).
    public init?(text: String) {
        let parts = text.split(separator: Self.separator, maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        self.init(left: String(parts[0]), right: String(parts[1]))
    }

    /// The text form, `left`, a line feed, `right`.
    public var text: String { "\(left)\(Self.separator)\(right)" }
}
