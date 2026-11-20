import Tracks

/// How an activity gets its category when the user has not chosen one, and which categories are not laid on lines.
///
/// The package knows no sport: the default category, the words and the raw categories are the app's. The standard policy is the one of
/// the decision on orienteering: a name with orienteering words suggests `orienteering`, which is raw; every other activity is a
/// `run` laid on the lines.
public struct CategoryPolicy: Sendable, Equatable {
    /// The category of an activity that nothing suggests anything for.
    public var defaultCategory: String
    /// Reads the text of an activity; `nil` for no suggestions.
    public var suggester: CategorySuggester?
    /// The tags whose text the suggester reads (strings only); by default the name that a GPX track gives.
    public var textTags: [String]
    /// The categories whose activities are not laid on lines (``ImportMode/raw``).
    public var rawCategories: Set<String>

    /// Creates a policy.
    public init(
        defaultCategory: String = "run", suggester: CategorySuggester? = CategorySuggester(), textTags: [String] = ["gpx.name"],
        rawCategories: Set<String> = ["orienteering"]
    ) {
        self.defaultCategory = defaultCategory
        self.suggester = suggester
        self.textTags = textTags
        self.rawCategories = rawCategories
    }

    /// The category that the text of an activity suggests, with the keyword that did it.
    public func suggestion(for activity: ActivityTrack) -> CategorySuggestion? {
        guard let suggester else { return nil }
        let texts = textTags.compactMap { tag -> String? in
            if case .string(let text)? = activity.tags[tag] { return text }
            return nil
        }
        return suggester.suggestion(for: texts)
    }

    /// The category an activity gets when nobody has chosen one: the suggestion, or the default.
    public func category(for activity: ActivityTrack) -> String { suggestion(for: activity)?.category ?? defaultCategory }

    /// How an activity of a category is put into the store.
    public func mode(of category: String) -> ImportMode { rawCategories.contains(category) ? .raw : .matched }
}
