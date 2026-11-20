import FeatureStore
import Foundation
import GeoCore
import Testing
import Tracks

@testable import FeatureStoreBuilder
@testable import TrackHeatMap
@testable import TrackMatching
@testable import TrackStorage

@Suite("Heat map player")
struct HeatMapPlayerTests {
    private let box = BoundingBox(south: 59.995, west: 9.995, north: 60.005, east: 10.015)

    /// A time-lapse of twelve months, an activity in each over the first 100 m or so more each month.
    private func lapse() async throws -> HeatMapTimeLapse {
        var writer = FeatureStoreWriter(
            boundingBox: BoundingBox(south: 59.9, west: 9.9, north: 60.1, east: 10.1), attribution: "© OpenStreetMap contributors, ODbL")
        let cell = try #require(TileID.containing(Coordinate(latitude: 60.0, longitude: 10.005), zoom: 13))
        try writer.add(
            StoredFeature(
                classID: FeatureClass.path.rawValue, kind: .line, objectType: .way, objectID: 7,
                parts: [GeometryPart(points: [PackedPoint(longitude: 100_000_000, latitude: 600_000_000), PackedPoint(longitude: 100_100_000, latitude: 600_000_000)])]),
            band: .detail, cell: cell)
        let source = try FeatureStoreFile(data: try writer.data())
        let store = try TrackStore(url: nil)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        for month in 1...12 {
            let start = Date(timeIntervalSince1970: 1_700_000_000)
            let samples = [TrackLeg.Sample(metre: 0, time: start), TrackLeg.Sample(metre: Double(month) * 40, time: start.addingTimeInterval(Double(month) * 16))]
            let leg = try #require(TrackLeg(wayID: 7, classID: FeatureClass.path.rawValue, direction: .forward, samples: samples, confidence: 0.9))
            let when = calendar.date(from: DateComponents(year: 2024, month: month, day: 15))!
            try await store.add(StoredActivity(appID: "m\(month)", started: when, category: "run", mapID: "m"), legs: [leg])
        }
        let area = try await HeatMapArea.make(store: store, source: source, box: box)
        return try #require(try await area.timeLapse())
    }

    /// Takes updates until the condition holds or the stream ends; gives them all.
    private func collect(_ player: HeatMapPlayer, until done: @escaping @Sendable (HeatMapPlayback) -> Bool) async -> [HeatMapPlayback] {
        var seen: [HeatMapPlayback] = []
        for await update in player.updates {
            seen.append(update)
            if done(update) { break }
        }
        return seen
    }

    @Test("A jump gives the frame of that month")
    func seek() async throws {
        let player = HeatMapPlayer(lapse: try await lapse())
        await player.seek(to: 5)
        let seen = await collect(player) { $0.index == 5 }
        #expect(seen.last?.index == 5 && seen.last?.isPlaying == false && seen.last?.frame.bucketCount ?? 0 > 0)
    }

    @Test("Requests that come faster than frames are made give the last one, and not more frames than requests")
    func coalescing() async throws {
        let player = HeatMapPlayer(lapse: try await lapse())
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<12 { group.addTask { await player.seek(to: index) } }
        }
        await player.seek(to: 7)
        let seen = await collect(player) { $0.index == 7 }
        #expect(seen.last?.index == 7)
        #expect(seen.count <= 13)
    }

    @Test("Playing steps through the months in order and stops at the last one by itself")
    func playing() async throws {
        let player = HeatMapPlayer(lapse: try await lapse(), pace: .milliseconds(1))
        await player.play()
        let seen = await collect(player) { $0.index == 11 && !$0.isPlaying }
        let indexes = seen.map(\.index)
        #expect(indexes == indexes.sorted() && indexes.last == 11 && seen.last?.isPlaying == false)
        #expect(await player.isPlaying == false)
    }

    @Test("Pausing stops the steps, and playing again after a pause goes on from there")
    func pauseAndGoOn() async throws {
        let player = HeatMapPlayer(lapse: try await lapse(), pace: .milliseconds(5))
        await player.play()
        let started = await collect(player) { $0.index >= 2 }
        await player.pause()
        let stopped = await collect(player) { !$0.isPlaying }
        let at = try #require(stopped.last?.index)
        #expect(at >= (started.last?.index ?? 0))
        try await Task.sleep(for: .milliseconds(60))
        #expect(await player.isPlaying == false)
        // Quick pause and play again: the old step must not stop the new one.
        await player.play()
        await player.pause()
        await player.play()
        let end = await collect(player) { $0.index == 11 && !$0.isPlaying }
        #expect(end.last?.index == 11)
    }

    @Test("Changing the span makes the frame of the month that is shown again")
    func span() async throws {
        let player = HeatMapPlayer(lapse: try await lapse())
        await player.seek(to: 6)
        _ = await collect(player) { $0.index == 6 }
        await player.setSpan(.last(months: 1))
        let seen = await collect(player) { $0.frame.months?.lowerBound == $0.frame.months?.upperBound }
        #expect(seen.last?.index == 6)
        // The cumulative frame of month 7 has 7 x 40 m; one month has only its own 280 m... both the same here, so check the months.
        #expect(seen.last?.frame.months?.lowerBound == TrackMonth(year: 2024, month: 7))
    }

    @Test("Closing ends the stream")
    func closing() async throws {
        let player = HeatMapPlayer(lapse: try await lapse())
        await player.close()
        var count = 0
        for await _ in player.updates { count += 1 }
        #expect(count == 0)
    }
}
