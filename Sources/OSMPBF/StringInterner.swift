import Foundation

/// Builds an ``InternedStrings`` table: gives each distinct string an ID.
///
/// Strings are compared **byte for byte**. Swift's own `String` equality treats
/// canonically equivalent strings (for example "é" as one character and as "e"
/// plus a combining accent) as equal, which would merge two different byte
/// sequences and silently change the data. OSM data is kept exactly as written,
/// so this uses its own hash table over the UTF-8 bytes.
struct StringInterner {
    private var bytes: [UInt8] = []
    private var offsets: [UInt32] = [0]
    /// Open-addressing table: 0 is an empty slot, otherwise the string ID plus one.
    private var slots: [UInt32] = Array(repeating: 0, count: 1024)

    /// Creates an interner whose first string, ID 0, is the empty string.
    init() {
        offsets = [0, 0]
        let emptyHash = Self.hash(UnsafeBufferPointer<UInt8>(start: nil, count: 0))
        slots[Int(truncatingIfNeeded: emptyHash) & (slots.count - 1)] = 1
    }

    /// The ID of a string, adding it if it is new.
    ///
    /// - Throws: ``AreaCutterError/extractTooLarge`` if the table would pass 4 GB.
    mutating func intern(_ string: String) throws -> UInt32 {
        var string = string
        return try string.withUTF8 { try intern(bytes: $0) }
    }

    private mutating func intern(bytes key: UnsafeBufferPointer<UInt8>) throws -> UInt32 {
        let mask = slots.count - 1
        var index = Int(truncatingIfNeeded: Self.hash(key)) & mask
        while true {
            let slot = slots[index]
            if slot == 0 { break }
            let id = Int(slot - 1)
            if matches(id: id, key) { return UInt32(id) }
            index = (index + 1) & mask
        }
        // New string: append it and record it in the empty slot found.
        let id = UInt32(offsets.count - 1)
        // The offsets are 32-bit, so the table cannot hold more than 4 GB of distinct strings.
        let newEnd = try CheckedOffset.make(bytes.count + key.count)
        bytes.append(contentsOf: key)
        offsets.append(newEnd)
        slots[index] = id + 1
        if (Int(id) + 1) * 2 > slots.count { grow() }
        return id
    }

    private func matches(id: Int, _ key: UnsafeBufferPointer<UInt8>) -> Bool {
        let start = Int(offsets[id])
        let end = Int(offsets[id + 1])
        guard end - start == key.count else { return false }
        return bytes.withUnsafeBufferPointer { stored in
            guard let storedBase = stored.baseAddress, let keyBase = key.baseAddress else { return key.isEmpty }
            return memcmp(storedBase + start, keyBase, key.count) == 0
        }
    }

    private mutating func grow() {
        var larger = [UInt32](repeating: 0, count: slots.count * 2)
        let mask = larger.count - 1
        for id in 0..<(offsets.count - 1) {
            let start = Int(offsets[id])
            let end = Int(offsets[id + 1])
            var index = bytes.withUnsafeBufferPointer { stored in
                Int(truncatingIfNeeded: Self.hash(UnsafeBufferPointer(rebasing: stored[start..<end])))
            } & mask
            while larger[index] != 0 { index = (index + 1) & mask }
            larger[index] = UInt32(id) + 1
        }
        slots = larger
    }

    /// FNV-1a over the bytes.
    private static func hash(_ key: UnsafeBufferPointer<UInt8>) -> UInt64 {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key {
            value ^= UInt64(byte)
            value = value &* 0x100_0000_01b3
        }
        return value
    }

    /// The finished table.
    func frozen() -> InternedStrings {
        InternedStrings(bytes: bytes, offsets: offsets)
    }
}
