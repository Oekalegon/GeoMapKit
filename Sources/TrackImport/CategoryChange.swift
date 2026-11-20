/// A category that is set for every activity that a selection picks (bulk tagging).
public struct CategoryChange: Sendable, Equatable {
    /// Which activities.
    public var selection: ActivitySelection
    /// The category they get.
    public var category: String

    /// Creates a change.
    public init(selection: ActivitySelection, category: String) {
        self.selection = selection
        self.category = category
    }
}
