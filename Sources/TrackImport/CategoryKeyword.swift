/// A word, or the start of a word, that suggests a category when a name or description has it.
public struct CategoryKeyword: Sendable, Equatable {
    /// How the text is compared with the words of a name.
    public enum Match: Sendable, Equatable {
        /// The whole word: `OL` matches "OL training" and "Sprint-OL", not "Col de la".
        case word
        /// The start of a word: `orienteer` matches "orienteering" and "orienteerings".
        case prefix
    }

    /// The text. Case never matters; accents do not either unless ``accentsMatter`` is set (`orientatie` matches "Oriëntatieloop").
    public var text: String
    /// How it is compared.
    public var match: Match
    /// Whether an accent must be the same. A short word needs it: with accents ignored `OL` would match the Swedish *öl* (beer).
    public var accentsMatter: Bool

    /// Creates a keyword.
    public init(_ text: String, _ match: Match = .word, accentsMatter: Bool = false) {
        self.text = text
        self.match = match
        self.accentsMatter = accentsMatter
    }
}
