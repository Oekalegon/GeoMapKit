/// A condition on one OSM tag of a feature: `gauge` is `1000` or `1067`, `surface` is `asphalt`.
///
/// With no values the condition is that the tag is there. Tags are known where the store keeps them: every tag in the detail band
/// (zoom 15 and up), and in the lower bands only the few the builder keeps in every band. A condition on a tag that the band
/// does not hold never matches.
public struct TagCondition: Sendable, Equatable {
    /// The key of the tag.
    public var key: String
    /// The values that match; empty if any value matches.
    public var values: [String]

    /// Creates a condition.
    public init(key: String, values: [String] = []) {
        self.key = key
        self.values = values
    }

    /// Whether a feature whose tag `key` has `value` (or `nil` if it has no such tag) meets the condition.
    public func isMet(by value: String?) -> Bool {
        guard let value else { return false }
        return values.isEmpty || values.contains(value)
    }
}
