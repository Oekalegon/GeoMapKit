/// Why a ``LineNetwork`` could not be made.
public enum LineNetworkError: Error, Equatable {
    /// The area covers more cells than the limit: the count of cells and the limit.
    case tooManyCells(Int, limit: Int)
    /// The box is not valid (south above north, a latitude or longitude out of range).
    case invalidBox
}
