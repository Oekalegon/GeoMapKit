import Foundation

/// Suggests a category from the name and description of an activity.
///
/// Words are the runs of letters and digits; case never matters, and accents do not unless the keyword says so (``CategoryKeyword/accentsMatter``). The first rule that has a keyword in the text wins, so
/// the order of the rules is the order of preference.
public struct CategorySuggester: Sendable, Equatable {
    /// The rules, most important first.
    public var rules: [CategoryRule]

    /// Creates a suggester.
    public init(rules: [CategoryRule] = [.orienteering]) { self.rules = rules }

    /// The suggestion for some texts (a name, a description), or `nil`.
    public func suggestion(for texts: [String]) -> CategorySuggestion? {
        let plain = texts.flatMap { Self.words($0, accents: false) }
        guard !plain.isEmpty else { return nil }
        let accented = texts.flatMap { Self.words($0, accents: true) }
        for rule in rules {
            for keyword in rule.keywords {
                let folded = Self.fold(keyword.text, accents: keyword.accentsMatter)
                guard !folded.isEmpty else { continue }
                let words = keyword.accentsMatter ? accented : plain
                let found = words.contains { keyword.match == .word ? $0 == folded : $0.hasPrefix(folded) }
                if found { return CategorySuggestion(category: rule.category, keyword: keyword) }
            }
        }
        return nil
    }

    private static func fold(_ text: String, accents: Bool) -> String {
        text.folding(options: accents ? [.caseInsensitive] : [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func words(_ text: String, accents: Bool) -> [String] {
        fold(text, accents: accents).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
