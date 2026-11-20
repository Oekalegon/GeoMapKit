import Foundation
import GeoCore
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

    @Test("A change that fails half way leaves the store as it was: the old activity and its counts are still there")
    func rollback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("trackstore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracks.sqlite")
        let store = try TrackStore(url: url)
        try await store.add(activity("a"), legs: [try leg(1, 0, 50)])
        // Another connection takes the leg table away, so the replacement fails after the old activity was removed.
        let other = try SQLiteDatabase(path: url.path)
        try other.execute("DROP TABLE leg")
        await #expect(throws: TrackStoreError.self) { try await store.add(activity("a"), legs: [try leg(2, 0, 30)]) }
        let found = try await store.activity(appID: "a")
        let counts = try await store.counts(ways: [1, 2])
        #expect(found != nil && counts.map(\.wayID) == [1, 1, 1, 1, 1], "the old activity and counts are kept")
    }

    @Test("Tags that cannot be read are an error, not an empty set")
    func damagedTags() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("trackstore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracks.sqlite")
        let store = try TrackStore(url: url)
        try await store.add(activity("a"), legs: [])
        let other = try SQLiteDatabase(path: url.path)
        try other.execute("UPDATE activity SET tags = ?", [.blob(Data("not json".utf8))])
        await #expect(throws: TrackStoreError.damaged("the tags of the activity a")) { try await store.activity(appID: "a") }
    }

    @Test("A second connection waits for a change in progress instead of failing at once")
    func busy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("trackstore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracks.sqlite")
        let store = try TrackStore(url: url)
        let holder = try SQLiteDatabase(path: url.path)
        try holder.execute("BEGIN IMMEDIATE")
        let started = ContinuousClock.now
        await #expect(throws: TrackStoreError.self) { try await store.add(activity("a"), legs: []) }
        #expect(ContinuousClock.now - started >= .seconds(1), "it waited for the lock")
        try holder.execute("ROLLBACK")
    }

    @Test("A month that is read from JSON is carried like one that is made")
    func decodedMonth() throws {
        let decoded = try JSONDecoder().decode(TrackMonth.self, from: Data(#"{"year":2024,"month":13}"#.utf8))
        #expect(decoded == TrackMonth(year: 2025, month: 1))
        let again = try JSONDecoder().decode(TrackMonth.self, from: try JSONEncoder().encode(TrackMonth(year: 2023, month: 11)))
        #expect(again == TrackMonth(year: 2023, month: 11))
    }

    @Test("A leg is rounded at both ends to the nearest 10 m: the bucket counts when it is covered by more than half at an end")
    func rounding() async throws {
        let store = try TrackStore(url: nil)
        try await store.add(activity("a"), legs: [try leg(1, 141, 144), try leg(2, 143, 148)])
        #expect(try await store.counts(ways: [1]).isEmpty)
        #expect(try await store.counts(ways: [2]).map(\.bucket) == [14])
    }

    @Test("The buckets of the store are as long as the buckets that the heat map draws")
    func bucketLength() {
        #expect(BucketCount.length == TrackLeg.bucketLength)
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

    // MARK: Traces

    /// An off-track line along 60 N from `from` to `to` metres, `north` metres to the north, a point every 10 m.
    private func offTrack(_ from: Double, _ to: Double, north: Double = 0, at offset: Double = 0) throws -> OffTrackLine {
        let count = Int(abs(to - from) / 10)
        let points = (0...count).map {
            Coordinate(latitude: 60 + north / 111_195, longitude: 10 + (from + (to - from) * Double($0) / Double(count)) / 55_597)
        }
        return try #require(OffTrackLine(coordinates: points, start: start.addingTimeInterval(offset), elapsed: 100, length: abs(to - from)))
    }

    @Test("Activities that ran the same way across open ground make one trace, counted once for each activity and once for each pass")
    func traces() async throws {
        let store = try TrackStore(url: nil)
        try await store.add(activity("a"), legs: [], offTrack: [try offTrack(0, 300), try offTrack(300, 0, at: 500)])
        try await store.add(
            activity("b", at: start.addingTimeInterval(86_400)), legs: [], offTrack: [try offTrack(0, 300, north: 6)])
        let found = try await store.traces()
        #expect(found.count == 1 && found[0].activities == 2 && found[0].passes == 3, "\(found.map { ($0.activities, $0.passes) })")
        #expect(abs(found[0].length - 300) < 2 && found[0].coordinates.count >= 55)
        #expect(try await store.offTrackLineCount() == 3)
    }

    @Test("Traces can be asked for by category and month, and a trace that nobody asked for is left out")
    func tracesByCategory() async throws {
        let store = try TrackStore(url: nil)
        let june = Date(timeIntervalSince1970: 1_717_200_000)
        try await store.add(activity("trail", category: "trail", at: start), legs: [], offTrack: [try offTrack(0, 300)])
        try await store.add(activity("road", category: "road", at: june), legs: [], offTrack: [try offTrack(0, 300, north: 3), try offTrack(0, 200, north: 200)])
        // One trace for the trail run, two for the road run: the categories are made apart, so the road run's line over the same ground is its own.
        #expect(try await store.traces().count == 3)
        #expect(try await store.traces(categories: ["trail"]).map(\.passes) == [1])
        #expect(try await store.traces(categories: ["road"]).map(\.activities) == [1, 1])
        #expect(try await store.traces(categories: []).isEmpty)
        #expect(try await store.traces(months: TrackMonth(start)...TrackMonth(start)).count == 1)
    }

    @Test("The traces of each category are made apart: a line never joins a trace of another category")
    func tracesPerCategory() async throws {
        let store = try TrackStore(url: nil)
        try await store.add(activity("a", category: "trail"), legs: [], offTrack: [try offTrack(0, 300)])
        try await store.add(activity("b", category: "orienteering", at: start.addingTimeInterval(86_400)), legs: [], offTrack: [try offTrack(0, 300, north: 3)])
        let all = try await store.traces()
        #expect(all.count == 2 && all.allSatisfy { $0.activities == 1 && $0.passes == 1 })
        #expect(Set(all.map(\.id)).count == 2)
        // The same two lines in one category are one trace.
        let one = try TrackStore(url: nil)
        try await one.add(activity("a", category: "trail"), legs: [], offTrack: [try offTrack(0, 300)])
        try await one.add(activity("b", category: "trail", at: start.addingTimeInterval(86_400)), legs: [], offTrack: [try offTrack(0, 300, north: 3)])
        #expect(try await one.traces().count == 1)
    }

    @Test("A database of version 2 is made current when it is opened: its traces, made from all categories together, are made again")
    func versionThree() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("trackstore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracks.sqlite")
        do {
            let store = try TrackStore(url: url)
            try await store.add(activity("a", category: "trail"), legs: [], offTrack: [try offTrack(0, 300)])
            try await store.add(activity("b", category: "orienteering", at: start.addingTimeInterval(86_400)), legs: [], offTrack: [try offTrack(0, 300, north: 3)])
            #expect(try await store.traces().count == 2)
        }
        // Back to version 2, with the traces as it made them: one trace for both categories, and not stale.
        let database = try SQLiteDatabase(path: url.path)
        try database.execute("DELETE FROM trace_pass")
        try database.execute("DELETE FROM trace")
        try database.execute("INSERT INTO trace(id, line, length) VALUES (1, x'', 300)")
        try database.execute("UPDATE meta SET value = '0' WHERE key = 'traces_stale'")
        try database.execute("PRAGMA user_version = 2")
        let reopened = try TrackStore(url: url)
        #expect(try await reopened.traces().count == 2)
    }

    @Test("Removing or replacing an activity makes the traces again the next time they are asked for")
    func tracesFollowChanges() async throws {
        let store = try TrackStore(url: nil)
        try await store.add(activity("a"), legs: [], offTrack: [try offTrack(0, 300)])
        try await store.add(activity("b", at: start.addingTimeInterval(10)), legs: [], offTrack: [try offTrack(0, 300, north: 4)])
        #expect(try await store.traces().map(\.passes) == [2])
        try await store.remove(appID: "a")
        let afterRemoval = try await store.traces()
        #expect(afterRemoval.map(\.passes) == [1] && afterRemoval[0].id != 0)
        try await store.add(activity("b", at: start.addingTimeInterval(10)), legs: [], offTrack: [])
        let lines = try await store.offTrackLineCount()
        #expect(try await store.traces().isEmpty && lines == 0)
    }

    @Test("A database of version 1 is changed to version 2 when it is opened, and keeps its activities")
    func migration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("trackstore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracks.sqlite")
        do {
            let store = try TrackStore(url: url)
            try await store.add(activity("a"), legs: [try leg(1, 0, 50)])
        }
        // Make it a version 1 database: without the tables of version 2.
        let database = try SQLiteDatabase(path: url.path)
        for table in ["trace_pass", "trace", "offtrack", "meta"] { try database.execute("DROP TABLE \(table)") }
        try database.execute("PRAGMA user_version = 1")
        let reopened = try TrackStore(url: url)
        #expect(try await reopened.counts(ways: [1]).count == 5)
        try await reopened.add(activity("b"), legs: [], offTrack: [try offTrack(0, 300)])
        #expect(try await reopened.traces().count == 1)
    }

    @Test("A damaged off-track line is an error, not a trace that is left out")
    func damagedLine() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("trackstore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracks.sqlite")
        let store = try TrackStore(url: url)
        try await store.add(activity("a"), legs: [], offTrack: [try offTrack(0, 300)])
        _ = try await store.traces()
        let other = try SQLiteDatabase(path: url.path)
        try other.execute("UPDATE offtrack SET line = ?", [.blob(Data([1, 2, 3]))])
        await #expect(throws: TrackStoreError.self) { try await store.rebuildTraces() }
        try other.execute("UPDATE trace SET line = ?", [.blob(Data([1, 2, 3]))])
        await #expect(throws: TrackStoreError.damaged("the trace 1000")) { try await store.traces() }
    }

    @Test("A file that was made up to version 1 and not finished is finished when it is opened")
    func halfMade() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("trackstore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracks.sqlite")
        do { _ = try TrackStore(url: url) }
        // Back to what a start that was cut short between the two steps leaves: the tables of version 1 and the number 1.
        let database = try SQLiteDatabase(path: url.path)
        for table in ["trace_pass", "trace", "offtrack", "meta"] { try database.execute("DROP TABLE \(table)") }
        try database.execute("PRAGMA user_version = 1")
        let store = try TrackStore(url: url)
        try await store.add(activity("a"), legs: [try leg(1, 0, 50)], offTrack: [try offTrack(0, 300)])
        #expect(try await store.traces().count == 1)
    }

    @Test("The rules of the traces are kept in the file, and a store opened with other rules makes the traces again")
    func rulesAreKept() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("trackstore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tracks.sqlite")
        do {
            let store = try TrackStore(url: url)
            try await store.add(activity("a"), legs: [], offTrack: [try offTrack(0, 300)])
            try await store.add(activity("b", at: start.addingTimeInterval(10)), legs: [], offTrack: [try offTrack(0, 300, north: 20)])
            #expect(try await store.traces().count == 2, "20 m apart is beyond the 12 m of the standard rules")
        }
        let wide = try TrackStore(url: url, traceRules: TraceRules(joinDistance: 30))
        #expect(wide.traceRules.joinDistance == 30)
        #expect(try await wide.traces().count == 1, "with 30 m the second line joins")
        try await wide.add(activity("c", at: start.addingTimeInterval(20)), legs: [], offTrack: [try offTrack(0, 300, north: 5)])
        #expect(try await wide.traces().count == 1, "the new line is put together with the rules of the store, not the standard ones")
    }

    @Test("Removing an activity removes its off-track lines, and the ids of the traces of the others stay the same")
    func cascadeAndIds() async throws {
        let store = try TrackStore(url: nil)
        try await store.add(activity("a"), legs: [], offTrack: [try offTrack(0, 300)])
        try await store.add(activity("b", at: start.addingTimeInterval(10)), legs: [], offTrack: [try offTrack(0, 200, north: 300)])
        try await store.add(activity("c", at: start.addingTimeInterval(20)), legs: [], offTrack: [try offTrack(0, 200, north: 600)])
        let before = try await store.traces().map(\.id)
        #expect(before.count == 3)
        try await store.remove(appID: "c")
        let lines = try await store.offTrackLineCount()
        #expect(lines == 2)
        #expect(try await store.traces().map(\.id) == Array(before.prefix(2)))
        // A line added later does not get the id of one that was removed.
        try await store.add(activity("d", at: start.addingTimeInterval(30)), legs: [], offTrack: [try offTrack(0, 200, north: 900)])
        #expect(try await store.traces().map(\.id).last != before.last)
    }

    @Test("Making the traces again from thousands of lines takes seconds at most, also in a debug build")
    func rebuildCost() async throws {
        let store = try TrackStore(url: nil)
        for index in 0..<1_000 {
            // Five lines of 500 m each for every activity, across 1,000 places in rows so that some lines run along others.
            let lines = try (0..<5).map { try offTrack(0, 500, north: Double((index % 40) * 30 + $0 * 400 + (index / 40) * 3)) }
            try await store.add(activity("a\(index)", at: start.addingTimeInterval(Double(index))), legs: [], offTrack: lines)
        }
        let clock = ContinuousClock()
        let time = try await clock.measure { _ = try await store.traces() }
        #expect(time < .seconds(30), "making the traces of 5,000 lines took \(time)")
    }

    @Test("A line keeps its points to a centimetre when it is stored")
    func lineBlob() throws {
        let line = [Coordinate(latitude: 59.9139123, longitude: 10.7522456), Coordinate(latitude: -33.8688, longitude: -151.2093)]
        let back = try #require(LineBlob.decode(LineBlob.encode(line)))
        #expect(zip(line, back).allSatisfy { abs($0.latitude - $1.latitude) < 1e-7 && abs($0.longitude - $1.longitude) < 1e-7 })
        #expect(LineBlob.decode(Data([1, 2, 3])) == nil && LineBlob.decode(Data()) == [])
    }
}
