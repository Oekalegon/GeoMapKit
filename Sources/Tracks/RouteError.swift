import Foundation

/// Why a ``Route`` could not be made.
public enum RouteError: Error, Equatable, LocalizedError {
    /// There are no points.
    case empty
    /// The point at this index is not a valid position (not finite, or out of range).
    case invalidCoordinate(index: Int)
    /// The step to the point at this index crosses the antimeridian (longitude jumps by more than 180 degrees). The kit does not
    /// support that: distances and projections would be wrong.
    case crossesAntimeridian(index: Int)
    /// The segment starts are not strictly increasing indices into the points, starting at 0.
    case invalidSegmentStarts

    public var errorDescription: String? {
        switch self {
        case .empty: "The route has no points."
        case .invalidCoordinate(let index): "Point \(index) of the route is not a valid position."
        case .crossesAntimeridian(let index): "The route crosses the antimeridian at point \(index), which is not supported."
        case .invalidSegmentStarts: "The segment starts of the route are not valid."
        }
    }
}
