import FeatureStore
import Foundation
import GeoCore
import Testing
import Tracks

@testable import FeatureStoreBuilder
@testable import TrackHeatMap
@testable import TrackMatching
@testable import TrackStorage

@Suite("Heat map area and time-lapse")
struct HeatMapAreaTests {
    private let box = BoundingBox(south: 59.995, west: 9.995, north: 60.005, east: 10.015)

    /// A map with one path (way 7) of about 560 m along 60° N, from 10.0° E to 10.01° E, in one cell.
    private func map() throws -> FeatureStoreFile {
        var writer = FeatureStoreWriter(
            boundingBox: BoundingBox(south: 59.9, west: 9.9, north: 60.1, east: 10.1), attribution: "© OpenStreetMap contributors, ODbL")
        let cell = try #require(TileID.containing(Coordinate(latitude: 60.0, longitude: 10.005), zoom: 13))
        try writer.add(
            StoredFeature(
                classID: FeatureClass.path.rawValue, kind: .line, objectType: .way, objectID: 7,
                parts: [GeometryPart(points: [PackedPoint(longitude: 100_000_000, latitude: 600_000_000), PackedPoint(longitude: 100_100_000, latitude: 600_000_000)])]),
            band: .detail, cell: cell)
        return try FeatureStoreFile(data: try writer.data())
    }

    private func date(_ year: Int, _ month: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(year: year, month: month, day: 15))!
    }

    /// A leg along way 7 from `from` to `to` metres, 4 s for every 10 m.
    private func leg(_ from: Double, _ to: Double) throws -> TrackLeg {
        let steps = max(Int((abs(to - from) / 10).rounded()), 1)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = (0...steps).map { TrackLeg.Sample(metre: from + (to - from) * Double($0) / Double(steps), time: start.addingTimeInterval(Double($0) * 4)) }
        return try #require(TrackLeg(wayID: 7, classID: FeatureClass.path.rawValue, direction: to >= from ? .forward : .backward, samples: samples, confidence: 0.9))
    }

    private func add(_ store: TrackStore, _ id: String, _ category: String, _ when: Date, _ legs: [(Double, Double)]) async throws {
        try await store.add(StoredActivity(appID: id, started: when, category: category, mapID: "m"), legs: try legs.map { try leg($0.0, $0.1) })
    }

    /// January, February and April 2024 have activities; March has none.
    private func filled() async throws -> HeatMapArea {
        let store = try TrackStore(url: nil)
        try await add(store, "a", "run", date(2024, 1), [(0, 200)])
        try await add(store, "b", "run", date(2024, 2), [(0, 200)])
        try await add(store, "c", "trail", date(2024, 4), [(100, 300)])
        return try await HeatMapArea.make(store: store, source: try map(), box: box)
    }

    @Test("The store gives the counts for each month, and they add up to the counts over all months")
    func monthly() async throws {
        let area = try await filled()
        let monthly = try await area.store.monthlyCounts(ways: [7])
        #expect(Set(monthly.map(\.month)) == [TrackMonth(year: 2024, month: 1), TrackMonth(year: 2024, month: 2), TrackMonth(year: 2024, month: 4)])
        let total = try await area.store.counts(ways: [7])
        #expect(monthly.map(\.count.activities).reduce(0, +) == total.map(\.activities).reduce(0, +))
        let trail = try await area.store.monthlyCounts(ways: [7], categories: ["trail"])
        #expect(Set(trail.map(\.month)) == [TrackMonth(year: 2024, month: 4)])
        let none = try await area.store.monthlyCounts(ways: [7], categories: [])
        #expect(none.isEmpty)
    }

    @Test("The months of the store run from the first activity to the last, for the categories asked for")
    func months() async throws {
        let area = try await filled()
        let all = try await area.store.activityMonths()
        let trail = try await area.store.activityMonths(categories: ["trail"])
        let nothing = try await area.store.activityMonths(categories: ["ski"])
        let empty = try await TrackStore(url: nil).activityMonths()
        #expect(all == TrackMonth(year: 2024, month: 1)...TrackMonth(year: 2024, month: 4))
        #expect(trail == TrackMonth(year: 2024, month: 4)...TrackMonth(year: 2024, month: 4) && nothing == nil && empty == nil)
        #expect(TrackMonth(year: 2024, month: 11).adding(months: 3) == TrackMonth(year: 2025, month: 2))
        #expect(TrackMonth(year: 2024, month: 1).months(to: TrackMonth(year: 2023, month: 11)) == -2)
    }

    @Test("A frame counts activities or passes, and only the categories asked for")
    func frames() async throws {
        let store = try TrackStore(url: nil)
        // One activity that goes out and back over the same 200 m: one activity, two passes.
        try await add(store, "a", "run", date(2024, 1), [(0, 200), (200, 0)])
        try await add(store, "b", "trail", date(2024, 2), [(0, 100)])
        let area = try await HeatMapArea.make(store: store, source: try map(), box: box)
        let activities = try await area.frame(measure: .activities)
        let passes = try await area.frame(measure: .passes)
        #expect(activities.maximumCount == 2 && passes.maximumCount == 3, "\(activities.maximumCount) \(passes.maximumCount)")
        let run = try await area.frame(categories: ["run"], measure: .passes)
        #expect(run.maximumCount == 2 && run.bucketCount == 20)
        let february = try await area.frame(months: TrackMonth(year: 2024, month: 2)...TrackMonth(year: 2024, month: 2))
        #expect(february.maximumCount == 1 && february.bucketCount == 10 && february.months.lowerBound == february.months.upperBound)
        let none = try await area.frame(categories: ["ski"])
        #expect(none.bucketCount == 0 && none.maximumCount == 0)
    }

    @Test("A time-lapse has a frame for every month between the first and the last, also a month with nothing in it")
    func lapse() async throws {
        let lapse = try #require(try await (try await filled()).timeLapse())
        #expect(lapse.frameCount == 4 && lapse.month(at: 2) == TrackMonth(year: 2024, month: 3) && lapse.month(at: 99) == TrackMonth(year: 2024, month: 4))
        // Cumulative: the map fills up; March adds nothing; April adds 100 to 300 m, which makes 3 on the 100 to 200 m that two months used.
        var maxima: [Int] = [], buckets: [Int] = []
        for index in 0..<4 {
            let frame = await lapse.frame(at: index, span: .cumulative)
            maxima.append(frame.maximumCount)
            buckets.append(frame.bucketCount)
        }
        #expect(maxima == [1, 2, 2, 3] && buckets == [20, 20, 20, 30], "\(maxima) \(buckets)")
        // One month: March is empty.
        let march = await lapse.frame(at: 2, span: .last(months: 1))
        #expect(march.bucketCount == 0 && march.months == TrackMonth(year: 2024, month: 3)...TrackMonth(year: 2024, month: 3))
        // Two months: February and March.
        let two = await lapse.frame(at: 2, span: .last(months: 2))
        #expect(two.bucketCount == 20 && two.maximumCount == 1)
        #expect(two.months == TrackMonth(year: 2024, month: 2)...TrackMonth(year: 2024, month: 3))
        // The window at the start is cut at the first month.
        let start = await lapse.frame(at: 0, span: .last(months: 12))
        #expect(start.months.lowerBound == TrackMonth(year: 2024, month: 1))
    }

    @Test("A frame is the same however it is reached: forward, back, or by a jump")
    func seeking() async throws {
        let lapse = try #require(try await (try await filled()).timeLapse())
        func figures(_ index: Int, _ span: HeatMapTimeLapse.Span) async -> [Int] {
            let frame = await lapse.frame(at: index, span: span)
            return [frame.bucketCount, frame.maximumCount]
        }
        for span in [HeatMapTimeLapse.Span.cumulative, .last(months: 1), .last(months: 2), .last(months: 3)] {
            var forward: [[Int]] = []
            for index in 0..<4 { forward.append(await figures(index, span)) }
            // Backwards, then in a jump, and the same again.
            var backward: [[Int]] = []
            for index in (0..<4).reversed() { backward.append(await figures(index, span)) }
            #expect(backward.reversed() == forward, "\(span)")
            let jump = await figures(3, span)
            let back = await figures(0, span)
            #expect(jump == forward[3] && back == forward[0], "\(span)")
        }
    }

    @Test("The measure of a time-lapse is passes or activities, and a category with nothing gives no time-lapse")
    func lapseMeasure() async throws {
        let store = try TrackStore(url: nil)
        try await add(store, "a", "run", date(2024, 1), [(0, 100), (100, 0)])
        let area = try await HeatMapArea.make(store: store, source: try map(), box: box)
        let passes = try #require(try await area.timeLapse(measure: .passes))
        let activities = try #require(try await area.timeLapse(measure: .activities))
        let twice = await passes.frame(at: 0).maximumCount, once = await activities.frame(at: 0).maximumCount
        #expect(twice == 2 && once == 1)
        let none = try await area.timeLapse(categories: ["ski"])
        #expect(none == nil)
    }

    @Test("An area that is too large or not valid is refused, and the ways are those of the map")
    func areas() async throws {
        let store = try TrackStore(url: nil)
        await #expect(throws: (any Error).self) {
            _ = try await HeatMapArea.make(store: store, source: try map(), box: BoundingBox(south: 40, west: -20, north: 70, east: 30))
        }
        await #expect(throws: LineNetworkError.invalidBox) {
            _ = try await HeatMapArea.make(store: store, source: try map(), box: BoundingBox(south: 61, west: 10, north: 60, east: 11))
        }
        let area = try await HeatMapArea.make(store: store, source: try map(), box: box)
        #expect(area.wayIDs == [7] && area.ways.contains(way: 7))
    }
}
