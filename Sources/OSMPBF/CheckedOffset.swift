/// Converts counts to the 32-bit offsets the extract uses.
enum CheckedOffset {
    static func make(_ count: Int) throws -> UInt32 {
        guard let offset = UInt32(exactly: count) else { throw AreaCutterError.extractTooLarge }
        return offset
    }
}
