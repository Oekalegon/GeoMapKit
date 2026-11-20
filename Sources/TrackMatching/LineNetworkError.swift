import Foundation

/// Why a ``LineNetwork`` could not be made.
public enum LineNetworkError: Error, Equatable, LocalizedError {
    /// The area covers more cells than the limit: the count of cells and the limit.
    case tooManyCells(Int, limit: Int)
    /// The box is not valid (south above north, a latitude or longitude out of range).
    case invalidBox

    public var errorDescription: String? {
        switch self {
        case .tooManyCells(let cells, let limit): "The area is too large to read: it covers \(cells) cells and the limit is \(limit)."
        case .invalidBox: "The area is not valid."
        }
    }
}
