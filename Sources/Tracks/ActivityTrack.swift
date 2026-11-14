import Foundation
import GeoCore

/// A recorded activity: points that all have a time, in order. This is the input of the heat map and of the segment statistics, and it
/// is the same whether it comes from a GPX file or from the workout store of the system (the app makes one from each, so the kit
/// knows nothing about HealthKit).
public struct ActivityTrack: Sendable, Equatable, Identifiable {
    /// The id: the one given, or one made from the start time, the number of points and the first position.
    public let id: String
    /// The name, if the source has one.
    public let name: String?
    /// The kind of activity as the source says (for example `running`), if it does.
    public let kind: String?
    /// The points that have a time, in order, with times that never go back.
    public let points: [TrackPoint]
    /// The time of the first point.
    public let startDate: Date
    /// The time from the first point to the last, in seconds, more than 0.
    public let duration: TimeInterval
    /// The length of the line through the points in metres.
    public let distance: Double

    /// Makes an activity from points, or says why they are not one.
    ///
    /// Points with no time are dropped (the rules allow a few). A time that goes back by no more than the tolerance is set to the time
    /// before it.
    ///
    /// - Parameters:
    ///   - id: The id; by default made by ``makeID(startDate:pointCount:first:)``.
    ///   - name: The name.
    ///   - kind: The kind of activity.
    ///   - points: The points in order.
    ///   - rules: What makes a track an activity.
    /// - Throws: ``NotAnActivity``.
    public init(id: String? = nil, name: String? = nil, kind: String? = nil, points: [TrackPoint], rules: ActivityRules = .standard) throws {
        guard !points.isEmpty else { throw NotAnActivity.tooFewPoints(0) }
        let timed = points.filter { $0.time != nil }
        let fraction = Double(timed.count) / Double(points.count)
        guard fraction >= rules.minimumTimedFraction else { throw NotAnActivity.tooFewTimes(fraction: fraction) }
        guard timed.count >= max(rules.minimumPoints, 1) else { throw NotAnActivity.tooFewPoints(timed.count) }
        var fixed: [TrackPoint] = []
        fixed.reserveCapacity(timed.count)
        for (index, point) in timed.enumerated() {
            guard var time = point.time else { continue }
            if let previous = fixed.last?.time, time < previous {
                let back = previous.timeIntervalSince(time)
                guard back <= rules.timeTolerance else { throw NotAnActivity.timeGoesBack(index: index, seconds: back) }
                time = previous
            }
            var copy = point
            copy.time = time
            fixed.append(copy)
        }
        guard let first = fixed.first?.time, let last = fixed.last?.time, last > first else { throw NotAnActivity.noDuration }
        var distance = 0.0
        for (previous, current) in zip(fixed, fixed.dropFirst()) { distance += previous.coordinate.distance(to: current.coordinate) }
        self.id = id ?? Self.makeID(startDate: first, pointCount: fixed.count, first: fixed[0].coordinate)
        self.name = name
        self.kind = kind
        self.points = fixed
        startDate = first
        duration = last.timeIntervalSince(first)
        self.distance = distance
    }

    /// An id for an activity that has none: `gpx-` and 16 hexadecimal digits of a hash (FNV-1a) of the start time in milliseconds, the
    /// number of points and the first position to about 10 cm. The same activity read twice gives the same id, which is how a duplicate
    /// is found.
    public static func makeID(startDate: Date, pointCount: Int, first: Coordinate) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ value: Int64) {
            for shift in stride(from: 0, to: 64, by: 8) {
                hash = (hash ^ UInt64(truncatingIfNeeded: (value >> Int64(shift)) & 0xff)) &* 0x0000_0100_0000_01B3
            }
        }
        mix(Int64((startDate.timeIntervalSince1970 * 1000).rounded()))
        mix(Int64(pointCount))
        mix(Int64((first.latitude * 1e6).rounded()))
        mix(Int64((first.longitude * 1e6).rounded()))
        return "gpx-" + String(format: "%016llx", hash)
    }
}
