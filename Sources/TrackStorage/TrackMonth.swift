import Foundation

/// A calendar month in UTC, the unit in which the counts of the store are kept.
///
/// The month an activity started in is the month of all of it, so months add up to years and counts of an activity are never split.
public struct TrackMonth: Sendable, Hashable, Comparable, Codable {
    /// The year.
    public let year: Int
    /// The month, 1 to 12.
    public let month: Int

    /// Creates a month; a month outside 1 to 12 is carried into the year.
    public init(year: Int, month: Int) {
        let index = year * 12 + (month - 1)
        self.init(index: index)
    }

    /// The month that contains a moment, in UTC.
    public init(_ date: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1)
    }

    /// The months counted from year 0, which is how the store keeps them.
    var index: Int { year * 12 + (month - 1) }

    init(index: Int) {
        // Floor division, so a month before year 0 is carried the right way.
        let years = Int((Double(index) / 12).rounded(.down))
        year = years
        month = index - years * 12 + 1
    }

    private enum CodingKeys: String, CodingKey { case year, month }

    /// Decodes a month and carries one outside 1 to 12 into the year, as ``init(year:month:)`` does.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(year: try container.decode(Int.self, forKey: .year), month: try container.decode(Int.self, forKey: .month))
    }

    public static func < (lhs: TrackMonth, rhs: TrackMonth) -> Bool { lhs.index < rhs.index }

    /// The month that is some months later (earlier for a negative number).
    public func adding(months: Int) -> TrackMonth { TrackMonth(index: index + months) }

    /// The number of months from this month to another: 0 for the same month, negative if the other is earlier.
    public func months(to other: TrackMonth) -> Int { other.index - index }
}
