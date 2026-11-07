/// The tags of one object, read from the interned tables without building a dictionary.
///
/// Tags are kept in key order, so iteration is deterministic.
public struct TagList: Sequence, Sendable {
    let keys: ArraySlice<UInt32>
    let values: ArraySlice<UInt32>
    let strings: InternedStrings

    /// The number of tags.
    public var count: Int { keys.count }

    /// Whether there are no tags.
    public var isEmpty: Bool { keys.isEmpty }

    /// The value of a tag, or `nil` if the object has no such tag.
    ///
    /// Keys are compared byte for byte (UTF-8), not with Swift's `String` equality, which
    /// treats canonically equivalent strings as equal. A linear search; objects have few tags.
    public subscript(key: String) -> String? {
        for (index, keyID) in keys.enumerated() {
            if let stored = strings.string(at: keyID), stored.utf8.elementsEqual(key.utf8) {
                return strings.string(at: values[values.startIndex + index])
            }
        }
        return nil
    }

    /// The tags as an ordered list, byte for byte, in the order they are stored (key byte order).
    public var orderedTags: [OSMTag] {
        map { OSMTag(key: $0.key, value: $0.value) }
    }

    /// The tags as a dictionary.
    ///
    /// A `[String: String]` uses Swift `String` equality, so two keys that differ only in
    /// Unicode normalization collapse into one entry here. Iterating the list does not.
    public var dictionary: [String: String] {
        var result: [String: String] = [:]
        result.reserveCapacity(count)
        for tag in self { result[tag.key] = tag.value }
        return result
    }

    public func makeIterator() -> Iterator {
        Iterator(list: self, position: 0)
    }

    public struct Iterator: IteratorProtocol {
        let list: TagList
        var position: Int

        public mutating func next() -> (key: String, value: String)? {
            guard position < list.keys.count else { return nil }
            defer { position += 1 }
            guard let key = list.strings.string(at: list.keys[list.keys.startIndex + position]),
                  let value = list.strings.string(at: list.values[list.values.startIndex + position]) else {
                preconditionFailure("a tag refers to a string ID that is not in the table")
            }
            return (key, value)
        }
    }
}
