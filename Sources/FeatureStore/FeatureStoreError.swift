/// Why a feature store file could not be read or written.
///
/// Files arrive from other devices and from downloads, so every structural
/// problem is reported as an error and never as a crash.
public enum FeatureStoreError: Error, Equatable, Sendable {
    /// The file does not start with the feature store magic bytes.
    case badMagic
    /// The file was written with a format version this reader does not support.
    case unsupportedVersion(Int)
    /// The file ends before the data it announces.
    case truncated
    /// The CRC-32 of the file does not match the checksum at its end.
    case checksumMismatch
    /// The file is internally inconsistent; the text says where.
    case corrupt(String)
    /// The caller passed data the format cannot hold.
    case invalidInput(String)
}
