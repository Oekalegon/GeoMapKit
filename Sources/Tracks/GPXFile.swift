import Foundation

/// The contents of a GPX file (versions 1.0 and 1.1): its tracks, routes and waypoints.
///
/// The file is untrusted. It is read with the limits of ``GPXLimits``, external entities are not resolved, and the `extensions` of
/// vendors are skipped. Anything that is wrong gives a ``GPXError`` with the line; a bad file never gives a partial result.
public struct GPXFile: Sendable, Equatable {
    /// The `creator` attribute of the `gpx` element, if any.
    public var creator: String?
    /// The name in the metadata, if any.
    public var name: String?
    /// The recorded tracks.
    public var tracks: [GPXTrack]
    /// The planned routes.
    public var routes: [GPXRoute]
    /// The waypoints.
    public var waypoints: [GPXWaypoint]

    /// Creates a file.
    public init(creator: String? = nil, name: String? = nil, tracks: [GPXTrack] = [], routes: [GPXRoute] = [], waypoints: [GPXWaypoint] = []) {
        self.creator = creator
        self.name = name
        self.tracks = tracks
        self.routes = routes
        self.waypoints = waypoints
    }

    /// Reads GPX from memory.
    ///
    /// - Parameters:
    ///   - data: The file.
    ///   - limits: How much to accept.
    /// - Throws: ``GPXError``.
    public init(data: Data, limits: GPXLimits = .standard) throws {
        guard data.count <= limits.maximumBytes else { throw GPXError.tooLarge(bytes: data.count, limit: limits.maximumBytes) }
        self = try GPXParser(limits: limits).parse(data)
    }

    /// Reads a GPX file from disk.
    ///
    /// - Parameters:
    ///   - url: The file.
    ///   - limits: How much to accept. The size is checked before the file is read.
    /// - Throws: ``GPXError``.
    public init(contentsOf url: URL, limits: GPXLimits = .standard) throws {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        if let size, size > limits.maximumBytes { throw GPXError.tooLarge(bytes: size, limit: limits.maximumBytes) }
        let data: Data
        do { data = try Data(contentsOf: url, options: .mappedIfSafe) } catch { throw GPXError.unreadable(error.localizedDescription) }
        try self.init(data: data, limits: limits)
    }

    /// The waypoints that lie within a distance of a route, as route waypoints (not required): a file has its `wpt` elements beside
    /// the track, and this says which belong to it.
    ///
    /// - Parameters:
    ///   - route: The route.
    ///   - maximumDistance: How far from the route a waypoint may be, in metres.
    /// - Returns: The waypoints with their distance along the route, in the order of the file.
    public func waypoints(near route: Route, maximumDistance: Double = 100) -> [RouteWaypoint] {
        waypoints.compactMap { waypoint in
            let projection = route.project(waypoint.point.coordinate)
            guard projection.distance <= maximumDistance else { return nil }
            return RouteWaypoint(name: waypoint.name, coordinate: waypoint.point.coordinate, distanceAlong: projection.distanceAlong)
        }
    }
}
