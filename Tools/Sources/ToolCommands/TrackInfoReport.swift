import Foundation
import GeoCore
import Tracks

/// What the `track info` command found in a GPX file.
public struct TrackInfoReport: Sendable {
    /// What is said about a track that is an activity: not its points.
    public struct ActivitySummary: Sendable, Equatable {
        public let id: String
        public let startDate: Date
        /// Seconds.
        public let duration: TimeInterval
        /// Metres.
        public let distance: Double
    }

    /// One track of the file.
    public struct TrackLine: Sendable {
        public let name: String?
        public let type: String?
        public let points: Int
        public let segments: Int
        /// The length in metres, or `nil` if the track could not be made a route (for example it crosses the antimeridian).
        public let length: Double?
        public let box: BoundingBox?
        /// The share of the points that have a time, from 0 to 1.
        public let timedFraction: Double
        /// The activity if the track is one, or the reason it is not.
        public let activity: Result<ActivitySummary, NotAnActivity>
        /// Why the track is no route, if it is not.
        public let routeProblem: String?
    }

    /// One planned route of the file.
    public struct RouteLine: Sendable {
        public let name: String?
        public let points: Int
        public let length: Double?
        public let routeProblem: String?
    }

    public let fileName: String
    public let fileSize: Int64
    public let creator: String?
    public let name: String?
    public let tracks: [TrackLine]
    public let routes: [RouteLine]
    public let waypoints: Int
    /// How many waypoints lie within 100 m of some track.
    public let waypointsNearATrack: Int

    /// Creates a report.
    public init(
        fileName: String, fileSize: Int64, creator: String?, name: String?, tracks: [TrackLine], routes: [RouteLine], waypoints: Int,
        waypointsNearATrack: Int
    ) {
        self.fileName = fileName
        self.fileSize = fileSize
        self.creator = creator
        self.name = name
        self.tracks = tracks
        self.routes = routes
        self.waypoints = waypoints
        self.waypointsNearATrack = waypointsNearATrack
    }
}
