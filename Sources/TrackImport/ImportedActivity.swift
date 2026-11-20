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
    /// The length that was laid on lines, in metres; 0 for a raw activity. It includes matched stretches that were too short or too
    /// uncertain to count (they have no legs and are not off-track lines either); ``countedLength`` is what counts.
    public let matchedLength: Double
    /// The recorded length of the stretches that count (they give the legs), in metres; 0 for a raw activity. What is left of
    /// ``matchedLength`` was matched but left out of the statistics.
    public let countedLength: Double
    /// The length on each feature class of the lines, in metres, to derive a category from the ground; empty for a raw activity.
    public let lengthByClass: [UInt8: Double]
    /// The parts of the track that cleaning dropped (too short to be a stretch).
    public let droppedSegments: Int

    /// Creates the result of an import.
    public init(
        activity: StoredActivity, legs: [TrackLeg], offTrack: [OffTrackLine], length: Double, matchedLength: Double, countedLength: Double,
        lengthByClass: [UInt8: Double], droppedSegments: Int
    ) {
        self.activity = activity
        self.legs = legs
        self.offTrack = offTrack
        self.length = length
        self.matchedLength = matchedLength
        self.countedLength = countedLength
        self.lengthByClass = lengthByClass
        self.droppedSegments = droppedSegments
    }
}
