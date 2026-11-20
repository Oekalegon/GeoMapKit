import Foundation
import GeoCore
import Testing

@testable import TrackImport

@Suite("Activity selection")
struct ActivitySelectionTests {
    private let day = 86_400.0
    private let base = Date(timeIntervalSince1970: 1_500_000_000)
    private let box = BoundingBox(south: 52, west: 5, north: 53, east: 6)

    @Test("An empty selection picks everything, also an activity with no known start position")
    func everything() {
        #expect(ActivitySelection().contains(start: base, position: nil))
    }

    @Test("Dates are a closed range: both ends are inside")
    func dates() {
        let selection = ActivitySelection(dates: base...base.addingTimeInterval(day))
        #expect(selection.contains(start: base, position: nil) && selection.contains(start: base.addingTimeInterval(day), position: nil))
        #expect(!selection.contains(start: base.addingTimeInterval(-1), position: nil) && !selection.contains(start: base.addingTimeInterval(day + 1), position: nil))
    }

    @Test("The place is where the activity started; an unknown start is not in any box")
    func place() {
        let selection = ActivitySelection(startsIn: box)
        #expect(selection.contains(start: base, position: Coordinate(latitude: 52.5, longitude: 5.5)))
        #expect(!selection.contains(start: base, position: Coordinate(latitude: 53.5, longitude: 5.5)))
        #expect(!selection.contains(start: base, position: nil))
    }

    @Test("Date and place must both fit")
    func both() {
        let selection = ActivitySelection(dates: base...base.addingTimeInterval(day), startsIn: box)
        let inside = Coordinate(latitude: 52.5, longitude: 5.5)
        #expect(selection.contains(start: base, position: inside))
        #expect(!selection.contains(start: base.addingTimeInterval(2 * day), position: inside))
    }

    @Test("Days are whole days of a calendar: from the start of the first to the end of the last, whatever the time of day that was given")
    func wholeDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Amsterdam"))
        let noon = calendar.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 12))!
        let evening = calendar.date(from: DateComponents(year: 2024, month: 3, day: 12, hour: 18))!
        let selection = ActivitySelection(days: noon...evening, calendar: calendar)
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date { calendar.date(from: DateComponents(year: 2024, month: 3, day: day, hour: hour, minute: minute))! }
        #expect(selection.contains(start: at(10, 0), position: nil) && selection.contains(start: at(12, 23, 59), position: nil))
        #expect(!selection.contains(start: at(9, 23, 59), position: nil) && !selection.contains(start: at(13, 0), position: nil))
        // The last day is a day long also when the clocks change (31 March 2024 is 23 hours long in Amsterdam).
        let change = ActivitySelection(days: at(31, 12)...at(31, 12), calendar: calendar)
        #expect(change.contains(start: at(31, 23, 30), position: nil) && !change.contains(start: at(30, 23, 30), position: nil))
    }
}
