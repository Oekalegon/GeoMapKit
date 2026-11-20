import FeatureStore
import Foundation
import GeoCore
import Testing

@testable import FeatureStoreBuilder
@testable import TrackHeatMap
@testable import TrackMatching
@testable import TrackOverlays
@testable import TrackStorage

@Suite("Heat map with traces")
struct HeatMapTraceTests {
    private let box = BoundingBox(south: 59.995, west: 9.995, north: 60.005, east: 10.015)
    private let farBox = BoundingBox(south: 60.5, west: 10.5, north: 60.6, east: 10.6)

    /// A map with one path (way 7) in the box; the traces below lie off it, 100 m to the north.
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

    private func date(_ month: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(year: 2024, month: month, day: 15))!
    }

    /// A line across open ground along 60.001° N, from 10.000° to 10.005° E (about 280 m).
    private func line(_ at: Date) throws -> OffTrackLine {
        let points = (0...28).map { Coordinate(latitude: 60.001, longitude: 10.0 + Double($0) * 0.005 / 28) }
        return try #require(OffTrackLine(coordinates: points, start: at, elapsed: 120, length: 280))
    }

    private func store(months: [Int], category: String = "trail") async throws -> TrackStore {
        let store = try TrackStore(url: nil)
        for month in months {
            try await store.add(
                StoredActivity(appID: "a\(month)", started: date(month), category: category, mapID: "m"), legs: [], offTrack: [try line(date(month))])
        }
        return store
    }

    @Test("The store counts the traces for each month")
    func monthly() async throws {
        let store = try await store(months: [1, 3])
        let counts = try await store.monthlyTraceCounts()
        #expect(counts.count == 2)
        #expect(counts.map(\.month) == [TrackMonth(year: 2024, month: 1), TrackMonth(year: 2024, month: 3)])
        let none = try await store.monthlyTraceCounts(categories: [])
        let other = try await store.monthlyTraceCounts(categories: ["ski"])
        let march = try await store.monthlyTraceCounts(months: TrackMonth(year: 2024, month: 3)...TrackMonth(year: 2024, month: 3))
        #expect(none.isEmpty && other.isEmpty && march.count == 1 && march[0].passes == 1)
    }

    @Test("A frame draws the traces on the same scale and counts them; an area with only traces is not empty")
    func frameWithTraces() async throws {
        let store = try await store(months: [1, 2])
        let area = try await HeatMapArea.make(store: store, source: try map(), box: box)
        let frame = try await area.frame()
        #expect(frame.bucketCount == 0 && frame.traceCount == 1 && frame.maximumCount == 2)
        #expect(frame.emptiness(databaseCountedPieces: 0, databaseOffTrackLines: 2) == nil)
        let without = try await area.frame(includeTraces: false)
        #expect(without.traceCount == 0 && without.emptiness(databaseCountedPieces: 0, databaseOffTrackLines: 2) == .countsElsewhere)
        #expect(without.emptiness(databaseCountedPieces: 0) == .databaseHasNoCounts)
        let february = try await area.frame(months: TrackMonth(year: 2024, month: 2)...TrackMonth(year: 2024, month: 2))
        #expect(february.traceCount == 1 && february.maximumCount == 1)
        let ski = try await area.frame(categories: ["ski"])
        #expect(ski.traceCount == 0 && ski.emptiness(databaseCountedPieces: 0, databaseOffTrackLines: 2) == .nothingInFilter)
    }

    @Test("A trace away from the area is left out, and the measure chooses activities or passes")
    func areaAndMeasure() async throws {
        let store = try await store(months: [1])
        let far = try await HeatMapArea.make(store: store, source: try map(), box: farBox).frame()
        #expect(far.traceCount == 0)
        let area = try await HeatMapArea.make(store: store, source: try map(), box: box)
        let passes = try await area.frame(measure: .passes)
        #expect(passes.traceCount == 1 && passes.maximumCount == 1)
    }

    @Test("A time-lapse adds and takes away the traces with the months")
    func lapse() async throws {
        let store = try await store(months: [1, 3])
        let area = try await HeatMapArea.make(store: store, source: try map(), box: box)
        let lapse = try #require(try await area.timeLapse())
        let january = await lapse.frame(at: 0, span: .last(months: 1))
        let february = await lapse.frame(at: 1, span: .last(months: 1))
        let march = await lapse.frame(at: 2, span: .cumulative)
        let marchOnly = await lapse.frame(at: 2, span: .last(months: 1))
        #expect(january.traceCount == 1 && february.traceCount == 0 && march.traceCount == 1 && march.maximumCount == 2)
        #expect(marchOnly.traceCount == 1 && marchOnly.maximumCount == 1)
        let without = try #require(try await area.timeLapse(includeTraces: false))
        #expect(await without.frame(at: 0).traceCount == 0)
    }

    @Test("The overlay draws a trace as lines, and not a count below the first step")
    func overlay() throws {
        let ways = HeatMapWays(network: try LineNetwork(source: try map(), box: box, classes: LineNetwork.travelClasses))
        let coordinates = [Coordinate(latitude: 60.001, longitude: 10.0), Coordinate(latitude: 60.001, longitude: 10.005)]
        let drawn = HeatMapOverlay(buckets: [], ways: ways, traces: [HeatMapTraceLine(coordinates: coordinates, count: 1)])
        let zero = HeatMapOverlay(buckets: [], ways: ways, traces: [HeatMapTraceLine(coordinates: coordinates, count: 0)])
        #expect(drawn.runCount == 1 && zero.runCount == 0)
    }
}
