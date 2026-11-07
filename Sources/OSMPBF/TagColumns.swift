/// Tags of many objects in two flat arrays, with a start offset per object.
struct TagColumns {
    /// `offsets[i]..<offsets[i + 1]` is the range of object `i` in `keys` and `values`.
    var offsets: [UInt32] = [0]
    var keys: [UInt32] = []
    var values: [UInt32] = []

    /// Appends the tags of one object, which are already in key byte order.
    mutating func append(_ tags: [OSMTag], interner: inout StringInterner) throws {
        for tag in tags {
            keys.append(try interner.intern(tag.key))
            values.append(try interner.intern(tag.value))
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
