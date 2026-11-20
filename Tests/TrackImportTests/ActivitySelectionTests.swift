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
}
