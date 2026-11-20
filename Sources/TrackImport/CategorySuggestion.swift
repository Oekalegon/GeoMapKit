/// A category that the text of an activity suggests, and the keyword that did it (to show the user why).
public struct CategorySuggestion: Sendable, Equatable {
    /// The suggested category.
    public let category: String
    /// The keyword that was found.
    public let keyword: CategoryKeyword

    /// Creates a suggestion.
    public init(category: String, keyword: CategoryKeyword) {
        self.category = category
        self.keyword = keyword
    }
}
