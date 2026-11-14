import Foundation
import GeoCore

/// An ordered polyline with distances, waypoints and (when the file has them) heights and times: a planned route or a recorded track.
///
/// All distances are in metres along the line of straight steps between the points, by the great circle (see
/// ``Coordinate/distance(to:)``). A route may be made of several segments (a recording that was paused); the steps between the end of
/// one segment and the start of the next are part of the line, so the distance along the route is continuous, and
/// ``segmentStarts`` says where the breaks are, so a drawing can leave them out.
///
/// A route does not cross the antimeridian (see ``RouteError/crossesAntimeridian(index:)``).
public struct Route: Sendable, Equatable {
    /// The name, if any.
    public let name: String?
    /// The points in order, at least one.
    public let points: [TrackPoint]
    /// The distance along the route to each point in metres, so `distances[0]` is 0 and the array has as many elements as `points`.
    public let distances: [Double]
    /// The indices of the points where a segment starts, ascending, starting with 0.
    public let segmentStarts: [Int]
    /// The waypoints, in the order given. The caller can change which are required.
    public var waypoints: [RouteWaypoint]
    /// The smallest box that holds all the points.
    public let boundingBox: BoundingBox

    /// The length of the route in metres.
    public var length: Double { distances[distances.count - 1] }

    /// Creates a route.
    ///
    /// - Parameters:
    ///   - name: The name.
    ///   - points: The points in order, at least one, all valid positions.
    ///   - segmentStarts: The indices where a segment starts. By default the whole route is one segment.
    ///   - waypoints: The waypoints.
    /// - Throws: ``RouteError``.
    public init(name: String? = nil, points: [TrackPoint], segmentStarts: [Int]? = nil, waypoints: [RouteWaypoint] = []) throws {
        guard !points.isEmpty else { throw RouteError.empty }
        if let starts = segmentStarts, !starts.isEmpty {
            guard starts.first == 0, zip(starts, starts.dropFirst()).allSatisfy({ $0 < $1 }), starts.last! < points.count else {
                throw RouteError.invalidSegmentStarts
            }
        }
        var distances = [0.0]
        distances.reserveCapacity(points.count)
        var south = Double.infinity, north = -Double.infinity, west = Double.infinity, east = -Double.infinity
        for (index, point) in points.enumerated() {
            let coordinate = point.coordinate
            guard coordinate.isValid else { throw RouteError.invalidCoordinate(index: index) }
            south = min(south, coordinate.latitude); north = max(north, coordinate.latitude)
            west = min(west, coordinate.longitude); east = max(east, coordinate.longitude)
            if index > 0 {
                let previous = points[index - 1].coordinate
                guard abs(coordinate.longitude - previous.longitude) <= 180 else { throw RouteError.crossesAntimeridian(index: index) }
                distances.append(distances[index - 1] + previous.distance(to: coordinate))
            }
        }
        self.name = name
        self.points = points
        self.distances = distances
        self.segmentStarts = (segmentStarts?.isEmpty ?? true) ? [0] : segmentStarts!
        self.waypoints = waypoints
        boundingBox = BoundingBox(south: south, west: west, north: north, east: east)
    }

    // MARK: Position along the route

    /// The position at a distance along the route, on the straight step between the two points around it.
    ///
    /// - Parameter distance: Metres from the start; below 0 gives the start and above ``length`` the end.
    /// - Returns: The position. Linear in latitude and longitude between two points, which is exact enough for steps of a few hundred
    ///   metres.
    public func coordinate(atDistance distance: Double) -> Coordinate {
        guard points.count > 1, distance > 0 else { return points[0].coordinate }
        guard distance < length else { return points[points.count - 1].coordinate }
        // The last point whose distance is not above the one asked for.
        var low = 0, high = distances.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if distances[middle] <= distance { low = middle } else { high = middle - 1 }
        }
        let start = points[low].coordinate, end = points[low + 1].coordinate
        let step = distances[low + 1] - distances[low]
        let fraction = step > 0 ? (distance - distances[low]) / step : 0
        return Coordinate(
            latitude: start.latitude + (end.latitude - start.latitude) * fraction,
            longitude: start.longitude + (end.longitude - start.longitude) * fraction)
    }

    /// The nearest point of the route to a position.
    ///
    /// With a `window` only that part of the route is looked at, which is how a route that passes the same place twice (out and back, a
    /// loop) is told apart: the follower asks for the part around where the runner is expected to be. Without one the nearest point of
    /// the whole route is found, and where two passes are equally near the one with the smaller distance along the route wins.
    ///
    /// The distance to a step is found on a flat plane around the position, which is within a few centimetres for steps up to a few
    /// hundred metres and gets worse for very long steps.
    ///
    /// - Parameters:
    ///   - coordinate: The position.
    ///   - window: The distances along the route (metres from the start) to look at, or `nil` for all of it. A window that lies
    ///     beyond an end of the route is moved to that end.
    /// - Returns: The projection.
    public func project(_ coordinate: Coordinate, in window: ClosedRange<Double>? = nil) -> RouteProjection {
        var lower = max(window?.lowerBound ?? 0, 0), upper = min(window?.upperBound ?? length, length)
        if lower > upper {
            // The window is beyond an end of the route: the end is the only place to look at.
            lower = min(lower, length)
            upper = lower
        }
        let toRadians = Double.pi / 180
        let metresPerDegree = Coordinate.earthRadius * toRadians
        let east = cos(coordinate.latitude * toRadians) * metresPerDegree
        // Flat coordinates in metres around the position.
        func flat(_ c: Coordinate) -> (x: Double, y: Double) {
            ((c.longitude - coordinate.longitude) * east, (c.latitude - coordinate.latitude) * metresPerDegree)
        }
        var best: RouteProjection?
        if points.count == 1 {
            let only = points[0].coordinate
            return RouteProjection(coordinate: only, distanceAlong: 0, distance: coordinate.distance(to: only), stepIndex: 0)
        }
        for index in 0..<(points.count - 1) {
            let startDistance = distances[index], endDistance = distances[index + 1]
            if endDistance < lower || startDistance > upper { continue }
            let a = flat(points[index].coordinate), b = flat(points[index + 1].coordinate)
            let dx = b.x - a.x, dy = b.y - a.y
            let squared = dx * dx + dy * dy
            var t = squared > 0 ? max(0, min(1, -(a.x * dx + a.y * dy) / squared)) : 0
            // Keep the point inside the window.
            let step = endDistance - startDistance
            if step > 0 {
                let tLow = max(0, (lower - startDistance) / step), tHigh = min(1, (upper - startDistance) / step)
                t = max(tLow, min(tHigh, t))
            }
            let px = a.x + dx * t, py = a.y + dy * t
            let distance = (px * px + py * py).squareRoot()
            if distance < (best?.distance ?? .infinity) {
                let start = points[index].coordinate, end = points[index + 1].coordinate
                best = RouteProjection(
                    coordinate: Coordinate(
                        latitude: start.latitude + (end.latitude - start.latitude) * t,
                        longitude: start.longitude + (end.longitude - start.longitude) * t),
                    distanceAlong: startDistance + step * t, distance: distance, stepIndex: index)
            }
        }
        // Some step always overlaps the window (it was moved into the route), so this is only for a route with no step at all.
        return best ?? RouteProjection(coordinate: points[0].coordinate, distanceAlong: 0, distance: coordinate.distance(to: points[0].coordinate), stepIndex: 0)
    }
}
