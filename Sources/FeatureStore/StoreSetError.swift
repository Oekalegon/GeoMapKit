/// Why a set of block files could not be opened or read.
public enum StoreSetError: Error, Equatable, Sendable {
    /// The manifest is not valid JSON or does not have the expected parts. The text says what is wrong.
    case invalidManifest(String)
    /// The manifest has a version this reader does not know.
    case unsupportedManifestVersion(Int)
    /// A block file named in the manifest is not there.
    case blockMissing(String)
    /// A block file does not agree with the manifest (storage zoom, format, rule table or bands) or is not a store file.
    case blockMismatch(file: String, reason: String)
    /// A level block was made from blocks that have changed since; the levels have to be built again.
    case levelOutOfDate(file: String)
}

extension StoreSetError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidManifest(let reason): "The manifest is not valid: \(reason)"
        case .unsupportedManifestVersion(let version): "The manifest has version \(version), which this reader does not support."
        case .blockMissing(let file): "The block file \(file) named in the manifest is missing."
        case .blockMismatch(let file, let reason): "The block file \(file) does not match the manifest: \(reason)"
        case .levelOutOfDate(let file): "The level file \(file) was made from blocks that have changed since: run 'geomapkit build-levels' again."
        }
    }
}
