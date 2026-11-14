import Foundation

/// Why a GPX file could not be read. Line numbers are those of the file, from 1.
public enum GPXError: Error, Equatable, LocalizedError {
    /// The file is larger than the limit.
    case tooLarge(bytes: Int, limit: Int)
    /// The file has more points than the limit.
    case tooManyPoints(limit: Int)
    /// The text is not well-formed XML.
    case malformed(line: Int, reason: String)
    /// The XML is fine but the root element is not `gpx`.
    case notGPX
    /// A point has no `lat` or `lon`, or one that is not a number, not finite or out of range (latitude -90 to 90, longitude -180 to 180).
    case invalidCoordinate(line: Int, latitude: String?, longitude: String?)
    /// A `time` that is not an ISO 8601 date and time.
    case invalidTime(line: Int, text: String)
    /// An `ele` that is not a finite number.
    case invalidElevation(line: Int, text: String)
    /// The file could not be read from disk.
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .tooLarge(let bytes, let limit): "The GPX file is \(bytes) bytes, more than the limit of \(limit)."
        case .tooManyPoints(let limit): "The GPX file has more than \(limit) points."
        case .malformed(let line, let reason): "The GPX file is not well-formed XML (line \(line)): \(reason)"
        case .notGPX: "The file is XML but not GPX: the root element is not gpx."
        case .invalidCoordinate(let line, let lat, let lon):
            "A point on line \(line) has no valid position (lat \(lat ?? "missing"), lon \(lon ?? "missing"))."
        case .invalidTime(let line, let text): "The time \"\(text)\" on line \(line) is not an ISO 8601 date and time."
        case .invalidElevation(let line, let text): "The elevation \"\(text)\" on line \(line) is not a number."
        case .unreadable(let reason): "The GPX file could not be read: \(reason)"
        }
    }
}
