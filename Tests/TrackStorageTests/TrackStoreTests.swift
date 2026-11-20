import Foundation
import Testing
import Tracks

@testable import TrackMatching
@testable import TrackStorage

@Suite("Track store")
struct TrackStoreTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// A leg along a way from `from` to `to` metres, 4 s for every 10 m.
    private func leg(_ way: Int64, _ from: Double, _ to: Double, at offset: Double = 0, confidence: Double = 0.9) throws -> TrackLeg {
        let forward = to >= from
        let steps = max(Int((abs(to - from) / 10).rounded()), 1)
        let samples = (0...steps).map { index in
            TrackLeg.Sample(metre: from + (to - from) * Double(index) / Double(steps), time: start.addingTimeInterval(offset + Double(index) * 4))
        }
        return try #require(TrackLeg(wayID: way, classID: 3, direction: forward ? .forward : .backward, samples: samples, confidence: confidence))
    }

    private func activity(_ id: String, category: String = "trail", at date: Date? = nil) -> StoredActivity {
        StoredActivity(appID: id, started: date ?? start, category: category, tags: ["sport": .string("run"), "n": .integer(3)], mapID: "europe")
    }

    @Test("A leg counts every bucket it covers once as an activity and once as a pass, and rounds to 10 m")
    func counts() async throws {
        let store = try TrackStore(url: nil)
        let kept = try await store.add(activity("a"), legs: [try leg(1, 103, 148)])
        #expect(kept == 1)
        let result = try await store.counts(ways: [1])
        // 103 rounds to 100, 148 to 150: buckets 10 to 14.
        #expect(result.map(\.bucket) == [10, 11, 12, 13, 14] && result.allSatisfy { $0.activities == 1 && $0.passes == 1 && $0.wayID == 1 })
        #expect(result[0].startMetre == 100)
    }

    @Test("Two passes of one activity are two passes and one activity; another activity adds one")
    func twoCounts() async throws {
        let store = try TrackStore(url: nil)
        try await store.add(activity("a"), legs: [try leg(1, 0, 50), try leg(1, 50, 0, at: 100)])
        try await store.add(activity("b"), legs: [try leg(1, 0, 30)])
        let result = try await store.counts(ways: [1])
        #expect(result.count == 5)
        #expect(result.prefix(3).allSatisfy { $0.activities == 2 && $0.passes == 3 })
        #expect(result.suffix(2).allSatisfy { $0.activities == 1 && $0.passes == 2 })
    }

    @Test("Removing an activity takes its part out of the counts and leaves the others; the buckets nobody used are gone")
    func removing() async throws {
        let store = try TrackStore(url: nil)
        try await store.add(activity("a"), legs: [try leg(1, 0, 50)])
        try await store.add(activity("b"), legs: [try leg(1, 0, 20)])
        #expect(try await store.remove(appID: "a"))
        #expect(try await store.counts(ways: [1]).map(\.bucket) == [0, 1])
        #expect(try await store.counts(ways: [1]).allSatisfy { $0.activities == 1 && $0.passes == 1 })
        #expect(try await !store.remove(appID: "a"))
        #expect(try await store.remove(appID: "b"))
        let legs = try await store.legCount(), activities = try await store.activityCount()
        #expect(try await store.counts(ways: [1]).isEmpty && legs == 0 && activities == 0)
    }

    @Test("Adding an activity again replaces it, so counts do not double")
    func replacing() async throws {
        let store = try TrackStore(url: nil)
        try await store.add(activity("a"), legs: [try leg(1, 0, 50)])
        try await store.add(activity("a"), legs: [try leg(2, 0, 30)])
        #expect(try await store.counts(ways: [1]).isEmpty)
        let activities = try await store.activityCount()
        #expect(try await store.counts(ways: [2]).count == 3 && activities == 1)
    }

    @Test("Categories and months are kept apart, and can be asked for singly or added")
    func categoriesAndMonths() async throws {
        let store = try TrackStore(url: nil)
        let june = Date(timeIntervalSince1970: 1_717_200_000)  // 2024-06-01
        try await store.add(activity("road", category: "road", at: start), legs: [try leg(1, 0, 20)])
        try await store.add(activity("trail", category: "trail", at: june), legs: [try leg(1, 0, 20)])
        #expect(try await store.counts(ways: [1]).map(\.activities) == [2, 2])
        #expect(try await store.counts(ways: [1], categories: ["road"]).map(\.activities) == [1, 1])
        #expect(try await store.counts(ways: [1], categories: []).isEmpty)
        let november = TrackMonth(start)
        #expect(november == TrackMonth(year: 2023, month: 11))
        #expect(try await store.counts(ways: [1], months: november...november).map(\.activities) == [1, 1])
        #expect(try await store.counts(ways: [1], months: november...TrackMonth(june)).map(\.activities) == [2, 2])
    }

    @Test("A leg that rounds to nothing is noise and is not kept")
    func noise() async throws {
        let store = try TrackStore(url: nil)
        #expect(try await store.add(activity("a"), legs: [try leg(1, 101, 104)]) == 0)
        #expect(try await store.counts(ways: [1]).isEmpty)
        #expect(try await store.activityCount() == 1)
    }

    @Test("Counts made again from the legs are the counts that were kept")
    func rebuild() async throws {
        let store = try TrackStore(url: nil)
        try await store.add(activity("a"), legs: [try leg(1, 0, 80), try leg(2, 40, 0, at: 100)])
        try await store.add(activity("b"), legs: [try leg(1, 30, 120)])
        let before = try await store.counts(ways: [1, 2])
        try await store.rebuildCounts()
        #expect(try await store.counts(ways: [1, 2]) == before)
    }

    @Test("The record and its tags come back as they went in")
    func record() async throws {
        let store = try TrackStore(url: nil)
        try await store.add(activity("a"), legs: [])
        let found = try #require(try await store.activity(appID: "a"))
        #expect(found == activity("a") && found.tags["n"] == .integer(3))
        #expect(try await store.activity(appID: "none") == nil)
    }

    @Test("The time profile has the seconds at every 25 m along the leg in the direction of travel")
    func profile() async throws {
        let store = try TrackStore(url: nil)
        try await store.add(activity("a"), legs: [try leg(1, 100, 0)])  // backward, 100 m, 40 s
        let profile = try #require(try await store.timeProfile(appID: "a", leg: 0))
        #expect(profile.count == 5 && profile[0] == 0)
        #expect(zip(profile, [0, 10, 20, 30, 40] as [Float]).allSatisfy { abs($0 - $1) < 0.01 }, "\(profile)")
        #expect(try await store.timeProfile(appID: "a", leg: 5) == nil)
    }

    @Test("A file keeps its data when it is opened again, and a database of a newer version is refused")
    func file() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("trackstore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracks.sqlite")
        do {
            let store = try TrackStore(url: url)
            try await store.add(activity("a"), legs: [try leg(1, 0, 50)])
        }
        let again = try TrackStore(url: url)
        #expect(try await again.counts(ways: [1]).count == 5)
        let newer = directory.appendingPathComponent("newer.sqlite")
        let database = try SQLiteDatabase(path: newer.path)
        try database.execute("PRAGMA user_version = 99")
        #expect(throws: TrackStoreError.newerVersion(found: 99, supported: TrackStore.version)) { try TrackStore(url: newer) }
        #expect(throws: TrackStoreError.self) { try TrackStore(url: directory.appendingPathComponent("missing/none.sqlite")) }
    }

    @Test("Many ways are looked up in groups")
    func manyWays() async throws {
        let store = try TrackStore(url: nil)
        try await store.add(activity("a"), legs: [try leg(5, 0, 20), try leg(1_200, 0, 20, at: 100)])
        let result = try await store.counts(ways: Array(0..<2_000))
        #expect(result.map(\.wayID) == [5, 5, 1_200, 1_200])
    }

    @Test("Months before year 0 and over 12 are carried")
    func months() {
        #expect(TrackMonth(year: 2024, month: 13) == TrackMonth(year: 2025, month: 1))
        #expect(TrackMonth(year: 2024, month: 0) == TrackMonth(year: 2023, month: 12))
        #expect(TrackMonth(year: 2024, month: 5) < TrackMonth(year: 2024, month: 6))
    }
}
