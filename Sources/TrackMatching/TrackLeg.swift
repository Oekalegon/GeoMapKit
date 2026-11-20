import Foundation

/// One go along one way: the part of a way that a track covered in one direction, with its times.
///
/// This is the unit that the segment statistics and the heat map count. A way is cut into buckets of fixed length by the store;
/// a leg says which buckets a track passed, when, and in which direction.
public struct TrackLeg: Sendable, Equatable {
    /// The way travelled in either direction along it: increasing distance from its first node is ``forward``.
    public enum Direction: Sendable, Equatable {
        /// Towards the end of the way (the distance along the way grows).
        case forward
        /// Towards the start of the way.
        case backward
    }

    /// A place along the leg with its time.
    public struct Sample: Sendable, Equatable {
        /// The distance along the way, in metres.
        public let metre: Double
        /// When the track was there; between two fixes this is interpolated by distance.
        public let time: Date
    }

    /// The OSM id of the way.
    public let wayID: Int64
    /// The feature class of the way.
    public let classID: UInt8
    /// The start of the range along the way, in metres (less than ``upperMetre``).
    public let lowerMetre: Double
    /// The end of the range along the way, in metres.
    public let upperMetre: Double
    /// The direction of travel.
    public let direction: Direction
    /// The places and times in the order of travel, at least two: the fixes and the nodes between them.
    public let samples: [Sample]
    /// The confidence of the stretch the leg comes from, from 0 to 1 (see ``MatchedStretch/confidence``).
    public let confidence: Double

    /// The length of the range, in metres.
    public var length: Double { upperMetre - lowerMetre }
    /// The time at the start of the leg.
    public var start: Date { samples[0].time }
    /// The time at the end of the leg.
    public var end: Date { samples[samples.count - 1].time }
    /// The time from the start to the end, in seconds.
    public var elapsed: TimeInterval { end.timeIntervalSince(start) }
}
