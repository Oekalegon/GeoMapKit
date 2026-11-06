/// An error raised while reading a PBF file.
///
/// File contents are untrusted: every length, count and index is checked
/// before it is used, and a malformed file fails with one of these errors
/// instead of producing partial data.
public enum PBFError: Error, Equatable, Sendable {
    /// The data ended in the middle of a value.
    case truncated

    /// A variable-length integer was longer than 10 bytes or overflowed 64 bits.
    case invalidVarint

    /// The protobuf structure is malformed, with a description of what was wrong.
    case malformed(String)

    /// A declared size exceeds the limit allowed by the PBF format.
    case sizeLimitExceeded(String)

    /// The blob uses a compression this reader does not support (for example `lzma_data`).
    case unsupportedCompression(String)

    /// The header lists a required feature this reader does not support.
    case unsupportedRequiredFeature(String)

    /// The compressed data could not be decompressed to the declared size.
    case decompressionFailed

    /// The first blob in the file is not an `OSMHeader`.
    case missingHeader

    /// A tag, role or string refers to a string-table index that does not exist.
    case invalidStringIndex(Int)

    /// Parallel arrays in a block disagree in length, or leftover data remained.
    case inconsistentBlock(String)
}
