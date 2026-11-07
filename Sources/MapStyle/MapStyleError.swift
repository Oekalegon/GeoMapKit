/// Why a style file could not be read or written.
///
/// The messages name the place in the file (for example `classes.roadMajor.stroke.width`) so a hand-written
/// style can be fixed without guessing.
public enum MapStyleError: Error, Equatable, CustomStringConvertible {
    /// The file is not a style: broken JSON, a missing or unknown key, or a value out of range.
    ///
    /// - `path`: where in the document the problem is; empty for the document as a whole.
    /// - `reason`: what is wrong.
    case invalid(path: String, reason: String)
    /// The file declares a format version this build does not read.
    case unsupportedVersion(Int)

    /// A one-line description with the location.
    public var description: String {
        switch self {
        case .invalid(let path, let reason): path.isEmpty ? "Invalid style: \(reason)" : "Invalid style at \(path): \(reason)"
        case .unsupportedVersion(let version):
            "Unsupported style format version \(version); this build reads version \(MapStyle.jsonFormatVersion)"
        }
    }
}
