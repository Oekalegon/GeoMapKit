import Foundation
import TrackOverlays
import TrackStorage

/// The heat map month by month: for each month from the first activity to the last, a frame that shows that month, the months so far, or
/// the last few months.
///
/// The counts of every month of the area are read once and kept in memory (buckets used in a month, not the whole area), so stepping from
/// one frame to the next costs a change of the running total and one overlay, not a query. The colour scale is fixed, so a bucket with
/// the same count has the same colour in every frame.
///
/// Frames are meant to be asked for in order (a player steps forward, a slider moves a little); a jump is paid for with the months it
/// skips over.
public actor HeatMapTimeLapse {
    /// Which months a frame counts, up to its own month.
    public enum Span: Sendable, Equatable {
        /// All months from the first one: the map fills up.
        case cumulative
        /// The last `months` months, the frame's month included: a moving window (1 is a single month).
        case last(months: Int)
    }

    /// The first and the last month; every month between them is a frame, also one with no activity.
    public nonisolated let range: ClosedRange<TrackMonth>
    /// The number of frames.
    public nonisolated var frameCount: Int { range.lowerBound.months(to: range.upperBound) + 1 }

    private struct Key: Hashable {
        var way: Int64
        var bucket: Int
    }

    private let measure: HeatMapMeasure
    private let ways: HeatMapWays
    private let wayCount: Int
    private let scale: HeatMapScale
    /// The counts of each month, as arrays of buckets, by the number of months after the first.
    private var months: [[(key: Key, count: Int)]]
    /// The running total and the months (by number) that it holds.
    private var total: [Key: Int] = [:]
    private var held: ClosedRange<Int>?

    init(range: ClosedRange<TrackMonth>, counts: [MonthlyBucketCount], measure: HeatMapMeasure, ways: HeatMapWays, scale: HeatMapScale) {
        self.range = range
        self.measure = measure
        self.ways = ways
        wayCount = ways.wayIDs.count
        self.scale = scale
        let length = range.lowerBound.months(to: range.upperBound) + 1
        var months = [[(key: Key, count: Int)]](repeating: [], count: length)
        for item in counts {
            let offset = range.lowerBound.months(to: item.month)
            guard offset >= 0, offset < length else { continue }
            let value = measure == .passes ? item.count.passes : item.count.activities
            if value > 0 { months[offset].append((Key(way: item.count.wayID, bucket: item.count.bucket), value)) }
        }
        self.months = months
    }

    /// The month of a frame.
    public nonisolated func month(at index: Int) -> TrackMonth { range.lowerBound.adding(months: min(max(index, 0), frameCount - 1)) }

    /// The frame for a month.
    ///
    /// - Parameters:
    ///   - index: The number of the month, from 0 for the first; one outside the range is brought into it.
    ///   - span: Which months are counted.
    public func frame(at index: Int, span: Span = .cumulative) -> HeatMapFrame {
        let last = min(max(index, 0), months.count - 1)
        let first: Int
        switch span {
        case .cumulative: first = 0
        case .last(let count): first = max(last - max(count, 1) + 1, 0)
        }
        move(to: first...last)
        let buckets = total.map { HeatMapBucket(wayID: $0.key.way, bucket: $0.key.bucket, count: $0.value) }
        return HeatMapArea.frame(
            buckets: buckets, ways: ways, wayCount: wayCount, months: range.lowerBound.adding(months: first)...range.lowerBound.adding(months: last),
            filtered: true, scale: scale)
    }

    /// Changes the running total from the months it holds to the months wanted, adding and taking away only the difference.
    private func move(to wanted: ClosedRange<Int>) {
        guard let current = held, current.overlaps(wanted) else {
            total = [:]
            for month in wanted { add(month, sign: 1) }
            held = wanted
            return
        }
        if wanted.lowerBound > current.lowerBound { for month in current.lowerBound..<wanted.lowerBound { add(month, sign: -1) } }
        if wanted.lowerBound < current.lowerBound { for month in wanted.lowerBound..<current.lowerBound { add(month, sign: 1) } }
        if wanted.upperBound > current.upperBound { for month in (current.upperBound + 1)...wanted.upperBound { add(month, sign: 1) } }
        if wanted.upperBound < current.upperBound { for month in (wanted.upperBound + 1)...current.upperBound { add(month, sign: -1) } }
        held = wanted
    }

    private func add(_ month: Int, sign: Int) {
        for (key, count) in months[month] {
            let value = total[key, default: 0] + sign * count
            if value > 0 { total[key] = value } else { total[key] = nil }
        }
    }
}
