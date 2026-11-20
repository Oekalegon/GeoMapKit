import Foundation
import TrackMatching
import TrackStorage

/// An activity made ready for the store: what ``TrackStore/add(_:legs:offTrack:)`` takes, and the figures of the match.
public struct ImportedActivity: Sendable, Equatable {
    /// The record.
    public let activity: StoredActivity
    /// The legs that count; none for a raw activity.
    public let legs: [TrackLeg]
    /// The stretches off the lines (for a raw activity, all of it).
    public let offTrack: [OffTrackLine]
    /// The recorded length of the cleaned track, in metres.
    public let length: Double
    /// The length that was laid on lines, in metres; 0 for a raw activity.
    public let matchedLength: Double
    /// The length on each feature class of the lines, in metres, to derive a category from the ground; empty for a raw activity.
    public let lengthByClass: [UInt8: Double]
    /// The parts of the track that cleaning dropped (too short to be a stretch).
    public let droppedSegments: Int
}
