import FeatureStore

/// Joins the pieces of one line that the store cut at cell borders.
///
/// Two pieces join when the first one continues after its last vertex, the second one continues before its first
/// vertex, and the two vertices lie within `tolerance` of each other. The tolerance is needed because each cell
/// computes its own clip point on the border and rounds it to 1e-7 degrees.
enum LineJoiner {
    /// The largest distance, in 1e-7 degrees on each axis, between the two border vertices of a join (about 2 cm).
    static let tolerance: Int32 = 3

    /// Joins pieces of one feature.
    ///
    /// - Parameter pieces: The pieces of one object, in any order.
    /// - Returns: One polyline per chain of joined pieces. Pieces with fewer than two vertices are dropped.
    static func join(_ pieces: [LinePiece]) -> [[PackedPoint]] {
        struct Chain {
            var points: [PackedPoint]
            var continuesAfter: Bool
        }
        var chains: [Chain] = []
        for piece in pieces.filter({ $0.points.count >= 2 }).sorted(by: { $0.offset < $1.offset }) {
            if piece.continuesBefore,
               let index = chains.lastIndex(where: { chain in
                   chain.continuesAfter && isNear(chain.points[chain.points.count - 1], piece.points[0])
               })
            {
                chains[index].points.append(contentsOf: piece.points.dropFirst())
                chains[index].continuesAfter = piece.continuesAfter
            } else {
                chains.append(Chain(points: piece.points, continuesAfter: piece.continuesAfter))
            }
        }
        return chains.map(\.points)
    }

    private static func isNear(_ a: PackedPoint, _ b: PackedPoint) -> Bool {
        abs(Int64(a.longitude) - Int64(b.longitude)) <= Int64(tolerance)
            && abs(Int64(a.latitude) - Int64(b.latitude)) <= Int64(tolerance)
    }
}
