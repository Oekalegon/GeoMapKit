import Foundation

/// Suggests a category from the name and description of an activity.
///
/// Words are the runs of letters and digits; case and accents do not matter. The first rule that has a keyword in the text wins, so
/// the order of the rules is the order of preference.
public struct CategorySuggester: Sendable, Equatable {
    /// The rules, most important first.
    public var rules: [CategoryRule]

    /// Creates a suggester.
    public init(rules: [CategoryRule] = [.orienteering]) { self.rules = rules }

    /// The suggestion for some texts (a name, a description), or `nil`.
    public func suggestion(for texts: [String]) -> CategorySuggestion? {
        let words = texts.flatMap(Self.words)
        guard !words.isEmpty else { return nil }
        for rule in rules {
            for keyword in rule.keywords {
                let folded = Self.fold(keyword.text)
                guard !folded.isEmpty else { continue }
                let found = words.contains { keyword.match == .word ? $0 == folded : $0.hasPrefix(folded) }
                if found { return CategorySuggestion(category: rule.category, keyword: keyword) }
            }
        }
        return nil
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func words(_ text: String) -> [String] {
        fold(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
