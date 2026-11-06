/// A read-only table of distinct strings, each stored once and referred to by a
/// `UInt32` ID.
///
/// Tags repeat the same few keys and values millions of times (in the Oslo test
/// area 2.5 million node tag strings were only 94,000 distinct ones), so objects
/// store IDs into this table instead of their own copies. The strings are kept as
/// one contiguous UTF-8 buffer with an offset per string. ID 0 is always the empty
/// string.
public struct InternedStrings: Sendable {
    let bytes: [UInt8]
    let offsets: [UInt32]

    init(bytes: [UInt8], offsets: [UInt32]) {
        self.bytes = bytes
        self.offsets = offsets
    }

    /// The number of distinct strings.
    public var count: Int { offsets.count - 1 }

    /// The string with the given ID.
    ///
    /// - Parameter id: An ID from this table.
    /// - Returns: The string, or `nil` if the ID is not in the table.
    public func string(at id: UInt32) -> String? {
        let index = Int(id)
        guard index + 1 < offsets.count else { return nil }
        return String(decoding: bytes[Int(offsets[index])..<Int(offsets[index + 1])], as: UTF8.self)
    }

    /// The memory used by the table, in bytes.
    public var memoryBytes: Int {
        bytes.count + offsets.count * MemoryLayout<UInt32>.stride
    }
}
