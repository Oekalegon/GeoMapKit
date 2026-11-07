/// One tag of an OSM object: a key and a value, exactly as stored in the file.
///
/// Swift `String` equality treats canonically equivalent strings (for example a precomposed
/// and a decomposed "é") as equal. Tags are therefore kept in arrays of ``OSMTag``, never in
/// a dictionary, wherever nothing may be lost; compare keys by their UTF-8 bytes.
public struct OSMTag: Hashable, Sendable {
    /// The key.
    public let key: String
    /// The value.
    public let value: String

    /// Creates a tag.
    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }

    /// The tags ordered by the UTF-8 bytes of their keys. Tags with identical keys keep their order.
    ///
    /// This order is deterministic and does not depend on Swift's Unicode-aware string comparison.
    static func sortedByKeyBytes(_ tags: [OSMTag]) -> [OSMTag] {
        // Most objects have zero or one tag, and files usually list tags in key order already.
        if tags.count < 2 || zip(tags, tags.dropFirst()).allSatisfy({ !$1.key.utf8.lexicographicallyPrecedes($0.key.utf8) }) {
            return tags
        }
        return tags.enumerated().sorted { lhs, rhs in
            if lhs.element.key.utf8.elementsEqual(rhs.element.key.utf8) { return lhs.offset < rhs.offset }
            return lhs.element.key.utf8.lexicographicallyPrecedes(rhs.element.key.utf8)
        }.map(\.element)
    }

    /// The value of the first tag whose key has exactly these UTF-8 bytes.
    static func value(forKey key: String, in tags: [OSMTag]) -> String? {
        tags.first { $0.key.utf8.elementsEqual(key.utf8) }?.value
    }

    /// A dictionary of tags. Lossy: later tags win, and keys that differ only in Unicode normalization collapse.
    static func dictionary(_ tags: [OSMTag]) -> [String: String] {
        Dictionary(tags.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
    }
}
