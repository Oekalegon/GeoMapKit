import Foundation
import GeoCore

/// Cleans a recorded track before it is matched to a map: cuts it where the recording jumped or stopped and went on elsewhere, and merges
/// the points where the runner stood still.
///
/// A recording that is paused and resumed somewhere else (a car ride between two hikes), or a bad fix, makes a straight line across the
/// map that a matcher would take for a run. A runner who stands still leaves tens of points within the wander of the fix, which would
/// count as tens of passes over one place. This type cuts the first and merges the second, and says what it did (``CleanedTrack``).
///
/// Only a cluster of points that lasts at least ``TrackCleaningRules/minimumStop`` is a stop and is merged. Points that are close for a
/// shorter time (a run recorded once a second, a slow climb) all stay, so the cleaner never thins a moving track. It does not smooth or
/// snap, and changes no position except by taking the mean of a stop.
public enum TrackCleaner {
    /// Cleans the points of one track.
    ///
    /// - Parameters:
    ///   - points: The points in order. A time on a point is used for gaps and speeds; points with no time are cut only by distance.
    ///   - rules: What counts as a break, a jump and a stop.
    /// - Returns: The stretches, the cuts, and how many points were merged or left out. No points, or none that make a stretch of two,
    ///   give no segments.
    public static func clean(_ points: [TrackPoint], rules: TrackCleaningRules = .standard) -> CleanedTrack {
        var segments: [TrackSegment] = []
        var breaks: [TrackBreak] = []
        var merged = 0
        var dropped = 0

        var output: [TrackPoint] = []
        var stops: [TrackStop] = []
        var cluster: Cluster?

        func flushCluster() {
            guard let finished = cluster else { return }
            cluster = nil
            if finished.count > 1, finished.seconds >= rules.minimumStop {
                // Standing still: the fixes are one point.
                stops.append(TrackStop(pointIndex: output.count, seconds: finished.seconds))
                merged += finished.count - 1
                output.append(finished.point)
            } else {
                // Points that are close for a moment are a run at a high sample rate, or a slow step: every point stays.
                output.append(contentsOf: finished.points)
            }
        }
        func closeSegment() {
            flushCluster()
            if output.count >= 2 { segments.append(TrackSegment(points: output, stops: stops)) } else if !output.isEmpty { dropped += 1 }
            output = []
            stops = []
        }

        for (index, point) in points.enumerated() {
            if index > 0, let reason = breakReason(from: points[index - 1], to: point, rules: rules) {
                closeSegment()
                breaks.append(TrackBreak(afterIndex: index - 1, reason: reason))
            }
            if var current = cluster, current.anchor.distance(to: point.coordinate) <= rules.stationaryRadius {
                current.add(point)
                cluster = current
            } else {
                flushCluster()
                cluster = Cluster(point)
            }
        }
        closeSegment()
        return CleanedTrack(segments: segments, breaks: breaks, mergedPoints: merged, droppedSegments: dropped)
    }

    /// Why the track is cut between two points that follow each other, or `nil` when it is not.
    private static func breakReason(from previous: TrackPoint, to next: TrackPoint, rules: TrackCleaningRules) -> TrackBreak.Reason? {
        let metres = previous.coordinate.distance(to: next.coordinate)
        guard let before = previous.time, let after = next.time else {
            return metres > rules.jumpDistanceUntimed ? .jump(metres: metres) : nil
        }
        let seconds = after.timeIntervalSince(before)
        if seconds > rules.maximumGap, metres > rules.gapDistance { return .gap(seconds: seconds, metres: metres) }
        if metres > rules.jumpDistance {
            if seconds <= 0 { return .speed(metresPerSecond: .infinity, metres: metres) }
            let speed = metres / seconds
            if speed > rules.maximumSpeed { return .speed(metresPerSecond: speed, metres: metres) }
        }
        return nil
    }

    /// Points that are one place: the first fixes the place, the others are within the stationary radius of it.
    private struct Cluster {
        let anchor: Coordinate
        private(set) var count = 1
        private var latitudeSum: Double
        private var longitudeSum: Double
        private let first: TrackPoint
        private(set) var points: [TrackPoint]
        private var lastTime: Date?

        init(_ point: TrackPoint) {
            anchor = point.coordinate
            first = point
            points = [point]
            latitudeSum = point.coordinate.latitude
            longitudeSum = point.coordinate.longitude
            lastTime = point.time
        }

        mutating func add(_ point: TrackPoint) {
            count += 1
            points.append(point)
            latitudeSum += point.coordinate.latitude
            longitudeSum += point.coordinate.longitude
            if let time = point.time { lastTime = time }
        }

        /// The time from the first point to the last, or 0 when there are no times (then nothing shows that the runner stood still).
        var seconds: Double {
            guard let start = first.time, let end = lastTime else { return 0 }
            return max(end.timeIntervalSince(start), 0)
        }

        /// The point that stands for the cluster: the mean position, the elevation and the time of the first point.
        var point: TrackPoint {
            guard count > 1 else { return first }
            var result = first
            result.coordinate = Coordinate(latitude: latitudeSum / Double(count), longitude: longitudeSum / Double(count))
            return result
        }
    }
}
