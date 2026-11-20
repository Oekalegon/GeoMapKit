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

        /// Creates a sample.
        public init(metre: Double, time: Date) {
            self.metre = metre
            self.time = time
        }
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

    /// Creates a leg.
    ///
    /// - Parameters:
    ///   - wayID: The OSM id of the way.
    ///   - classID: The feature class of the way.
    ///   - direction: The direction of travel.
    ///   - samples: The places and times in the order of travel; the range is made from them. At least two are needed (fewer make a leg
    ///     of no length that starts and ends at the one sample, or at no time at all, so they are refused).
    ///   - confidence: The confidence of the stretch, from 0 to 1.
    /// - Returns: `nil` for fewer than two samples.
    public init?(wayID: Int64, classID: UInt8, direction: Direction, samples: [Sample], confidence: Double) {
        guard samples.count >= 2, let low = samples.map(\.metre).min(), let high = samples.map(\.metre).max() else { return nil }
        self.init(wayID: wayID, classID: classID, lowerMetre: low, upperMetre: high, direction: direction, samples: samples, confidence: confidence)
    }

    init(
        wayID: Int64, classID: UInt8, lowerMetre: Double, upperMetre: Double, direction: Direction, samples: [Sample], confidence: Double
    ) {
        self.wayID = wayID
        self.classID = classID
        self.lowerMetre = lowerMetre
        self.upperMetre = upperMetre
        self.direction = direction
        self.samples = samples
        self.confidence = confidence
    }

    /// The length of the range, in metres.
    public var length: Double { upperMetre - lowerMetre }
    /// The time at the start of the leg.
    public var start: Date { samples[0].time }
    /// The time at the end of the leg.
    public var end: Date { samples[samples.count - 1].time }
    /// The time from the start to the end, in seconds.
    public var elapsed: TimeInterval { end.timeIntervalSince(start) }
}
