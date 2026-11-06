/// Tags of many objects in two flat arrays, with a start offset per object.
struct TagColumns {
    /// `offsets[i]..<offsets[i + 1]` is the range of object `i` in `keys` and `values`.
    var offsets: [UInt32] = [0]
    var keys: [UInt32] = []
    var values: [UInt32] = []

    /// Appends the tags of one object, sorted by key so the order is deterministic.
    mutating func append(_ tags: [String: String], interner: inout StringInterner) throws {
        for (key, value) in tags.sorted(by: { $0.key < $1.key }) {
            keys.append(interner.intern(key))
            values.append(interner.intern(value))
        }
        offsets.append(try CheckedOffset.make(keys.count))
    }

    /// Appends tags that are already interned.
    mutating func append(keys newKeys: ArraySlice<UInt32>, values newValues: ArraySlice<UInt32>) throws {
        keys.append(contentsOf: newKeys)
        values.append(contentsOf: newValues)
        offsets.append(try CheckedOffset.make(keys.count))
    }
}

/// Converts counts to the 32-bit offsets the extract uses.
enum CheckedOffset {
    static func make(_ count: Int) throws -> UInt32 {
        guard let offset = UInt32(exactly: count) else { throw AreaCutterError.extractTooLarge }
        return offset
    }
}
