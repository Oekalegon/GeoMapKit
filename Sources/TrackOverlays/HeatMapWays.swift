import GeoCore
import TrackMatching

/// The geometry of ways by distance along them: what turns a range of metres of a way into a line on the map.
///
/// It is made from a ``LineNetwork`` (whose edges know their distance along the way), so the buckets of the track store, which are
/// counted along the ways of a map, are drawn on the ways of the same map. A way is as long as the part of it that the network holds.
public struct HeatMapWays: Sendable {
    private struct Piece: Sendable {
        var offset: Double
        var length: Double
        var start: Coordinate
        var end: Coordinate
    }

    private let pieces: [Int64: [Piece]]

    /// Collects the edges of a network by way.
    public init(network: LineNetwork) {
        var byWay: [Int64: [Piece]] = [:]
        for edge in network.edges {
            byWay[edge.wayID, default: []].append(
                Piece(offset: edge.wayOffset, length: edge.length, start: network.coordinates[edge.from], end: network.coordinates[edge.to]))
        }
        pieces = byWay.mapValues { $0.sorted { $0.offset < $1.offset } }
    }

    /// Whether the network has a way.
    public func contains(way: Int64) -> Bool { pieces[way] != nil }

    /// The line of a range of a way, in the direction of the way.
    ///
    /// - Parameters:
    ///   - way: The OSM id.
    ///   - from: The start, in metres from the start of the way.
    ///   - to: The end, in metres.
    /// - Returns: The parts of the range that the network has: one polyline of at least two coordinates for each stretch of edges that
    ///   follow each other (the part of the way outside the network, or an edge the network does not have, splits the line). Empty for a
    ///   way that is not in the network or a range with no length.
    public func lines(way: Int64, from: Double, to: Double) -> [[Coordinate]] {
        guard let list = pieces[way], to > from else { return [] }
        var parts: [[Coordinate]] = []
        var current: [Coordinate] = []
        var currentEnd = -Double.infinity
        for piece in list {
            let end = piece.offset + piece.length
            if end <= from { continue }
            if piece.offset >= to { break }
            let low = max(piece.offset, from), high = min(end, to)
            guard high > low, piece.length > 0 else { continue }
            func point(_ metre: Double) -> Coordinate {
                let t = (metre - piece.offset) / piece.length
                return Coordinate(
                    latitude: piece.start.latitude + (piece.end.latitude - piece.start.latitude) * t,
                    longitude: piece.start.longitude + (piece.end.longitude - piece.start.longitude) * t)
            }
            if abs(low - currentEnd) > 0.5 {
                if current.count >= 2 { parts.append(current) }
                current = [point(low)]
            }
            current.append(point(high))
            currentEnd = high
        }
        if current.count >= 2 { parts.append(current) }
        return parts
    }
}
