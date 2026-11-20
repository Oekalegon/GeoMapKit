/// The keywords that suggest one category.
public struct CategoryRule: Sendable, Equatable {
    /// The category that is suggested.
    public var category: String
    /// The keywords; one of them is enough.
    public var keywords: [CategoryKeyword]

    /// Creates a rule.
    public init(category: String, keywords: [CategoryKeyword]) {
        self.category = category
        self.keywords = keywords
    }

    /// Orienteering: the words `OL` and `NK` (a championship), and the starts of the words for orienteering in English, Dutch, German and
    /// Norwegian or Swedish. A name such as "Col de la Madeleine" has none of them as a word. A suggestion, never a decision: the user or
    /// the app has the last word, because a run on the paths of a forest can have such a name too.
    public static let orienteering = CategoryRule(
        category: "orienteering",
        keywords: [
            CategoryKeyword("OL"), CategoryKeyword("NK"), CategoryKeyword("orienteer", .prefix), CategoryKeyword("orientatie", .prefix),
            CategoryKeyword("orientierung", .prefix), CategoryKeyword("orientering", .prefix),
        ])
}
