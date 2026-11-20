import Foundation
import Tracks

/// What the store keeps of an activity besides its legs: no points, only what the counts and a later match again need.
public struct StoredActivity: Sendable, Equatable {
    /// The id the app gives the activity. It is unique in the store: adding an activity with the same id replaces the earlier one.
    public var appID: String
    /// When the activity started.
    public var started: Date
    /// The category the app set (road, trail, track or whatever it chooses); the package gives it no meaning. It is part of the key of the
    /// counts, so categories are kept apart and a combination is a sum.
    public var category: String
    /// The app's tags, kept as they are.
    public var tags: [String: TagValue]
    /// The map the legs were made on (a name or an identity the app chooses), so that a map update can tell which activities to match again.
    public var mapID: String
    /// The version of the matching rules the legs were made with.
    public var matchedWith: Int

    /// Creates an activity record.
    public init(
        appID: String, started: Date, category: String, tags: [String: TagValue] = [:], mapID: String, matchedWith: Int = 1
    ) {
        self.appID = appID
        self.started = started
        self.category = category
        self.tags = tags
        self.mapID = mapID
        self.matchedWith = matchedWith
    }

    /// The month the activity started in (UTC).
    public var month: TrackMonth { TrackMonth(started) }
}
