import Foundation
import GeoCore
import Tracks

/// Which activities a bulk change applies to: those that started in a period and, if set, in a place.
///
/// The history of one person can hold a long run of events of one kind (a club's orienteering before some year); a date range and a box
/// around where they were held pick them out for one tag. The place is where the activity **started**, so a long run that passes
/// through the box does not count.
public struct ActivitySelection: Sendable, Equatable {
    /// The period in which the activity started, or `nil` for any time.
    public var dates: ClosedRange<Date>?
    /// The box that the start must be in, or `nil` for anywhere.
    public var startsIn: BoundingBox?

    /// Creates a selection; with no arguments it picks everything.
    public init(dates: ClosedRange<Date>? = nil, startsIn: BoundingBox? = nil) {
        self.dates = dates
        self.startsIn = startsIn
    }

    /// A selection of whole days: from the start of the first day to the end of the last, in a calendar (the days of the user, not UTC).
    ///
    /// - Parameters:
    ///   - days: The first and the last day; the time of day of each is ignored.
    ///   - startsIn: The box that the start must be in, or `nil` for anywhere.
    ///   - calendar: The calendar and time zone that say where a day begins.
    public init(days: ClosedRange<Date>, startsIn: BoundingBox? = nil, calendar: Calendar = .current) {
        let first = calendar.startOfDay(for: days.lowerBound)
        let afterLast = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: days.upperBound)) ?? days.upperBound
        self.init(dates: first...max(first, afterLast.addingTimeInterval(-0.001)), startsIn: startsIn)
    }

    /// Whether an activity that started at a time and a position is picked.
    ///
    /// - Parameter position: Where it started; `nil` when that is not known, which no box picks.
    public func contains(start: Date, position: Coordinate?) -> Bool {
        if let dates, !dates.contains(start) { return false }
        if let startsIn {
            guard let position, startsIn.contains(position) else { return false }
        }
        return true
    }

    /// Whether an activity is picked.
    public func contains(_ activity: ActivityTrack) -> Bool {
        contains(start: activity.startDate, position: activity.points.first?.coordinate)
    }
}
