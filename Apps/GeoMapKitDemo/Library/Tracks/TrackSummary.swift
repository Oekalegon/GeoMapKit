import Foundation
import GeoCore

/// What is known about a GPX file once it has been read: the tracks and routes in it that can be drawn.
struct TrackSummary: Equatable, Sendable, Codable {
    /// How many tracks and routes of the file are drawn.
    var lines = 0
    var points = 0
    /// The length of all of them, in metres.
    var length = 0.0
    /// The smallest box that holds all of them, or `nil` if nothing can be drawn.
    var box: BoundingBox?
    /// How many of the tracks are activities (their points have times, in order).
    var activities = 0
    /// When the first activity started.
    var startDate: Date?
    /// Parts of the file that could not be drawn, each with the reason (a track across the antimeridian).
    var problems: [String] = []
}
