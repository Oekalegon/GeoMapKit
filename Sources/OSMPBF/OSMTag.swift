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
        tags.enumerated().sorted { lhs, rhs in
            if lhs.element.key.utf8.elementsEqual(rhs.element.key.utf8) { return lhs.offset < rhs.offset }
            return lhs.element.key.utf8.lexicographicallyPrecedes(rhs.element.key.utf8)
        }.map(\.element)
    }

    /// A dictionary of tags. Lossy: later tags win, and keys that differ only in Unicode normalization collapse.
    static func dictionary(_ tags: [OSMTag]) -> [String: String] {
        Dictionary(tags.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
    }
}
