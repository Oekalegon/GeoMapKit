import Foundation
import GeoCore
import Tracks

/// Takes the off-track stretches out of a matched segment.
public enum OffTrackLines {
    /// The shortest stretch that is kept, in metres: a first value equal to ``MatchingRules/minimumRawLength``, below which the matcher
    /// takes a stretch between two matched ones into them. A shorter one is left over only at the start or end of a segment and is noise.
    public static let defaultMinimumLength = 30.0

    /// The raw stretches of a segment as lines.
    ///
    /// - Parameters:
    ///   - segment: The matched segment.
    ///   - points: The points of the cleaned segment that it was made from.
    ///   - minimumLength: The shortest recorded length of a stretch to keep, in metres.
    /// - Returns: A line for each raw stretch at least that long, in order. A stretch whose first or last point has no time is left out.
    public static func lines(of segment: MatchedSegment, points: [TrackPoint], minimumLength: Double = defaultMinimumLength) -> [OffTrackLine] {
        var result: [OffTrackLine] = []
        for (index, stretch) in segment.stretches.enumerated() where !stretch.isMatched && stretch.length >= minimumLength {
            guard stretch.pointRange.lowerBound < points.count, stretch.pointRange.upperBound - 1 < points.count,
                let start = points[stretch.pointRange.lowerBound].time, let end = points[stretch.pointRange.upperBound - 1].time
            else { continue }
            // From the end of the stretch before and to the start of the one after, so that the line meets the lines of the map.
            var coordinates: [Coordinate] = []
            if index > 0, let before = segment.stretches[index - 1].coordinates.last { coordinates.append(before) }
            coordinates += stretch.coordinates
            if let next = stretch.joinsTo { coordinates.append(next) }
            if let line = OffTrackLine(coordinates: coordinates, start: start, elapsed: end.timeIntervalSince(start), length: stretch.length) {
                result.append(line)
            }
        }
        return result
    }

    /// The off-track lines of all segments of a matched track.
    ///
    /// - Throws: ``TrackLegsError/segmentCountsDiffer(matched:cleaned:)`` when the tracks do not have the same number of segments.
    public static func lines(
        of matched: MatchedTrack, from cleaned: CleanedTrack, minimumLength: Double = defaultMinimumLength
    ) throws -> [OffTrackLine] {
        guard matched.segments.count == cleaned.segments.count else {
            throw TrackLegsError.segmentCountsDiffer(matched: matched.segments.count, cleaned: cleaned.segments.count)
        }
        return zip(matched.segments, cleaned.segments).flatMap { lines(of: $0, points: $1.points, minimumLength: minimumLength) }
    }
}
