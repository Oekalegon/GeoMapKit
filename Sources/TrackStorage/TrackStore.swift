import Foundation
import GeoCore
import TrackMatching
import Tracks

/// The segment database: for each activity its tags and its legs along ways, and the counts per bucket of a way that the heat map draws.
///
/// The store keeps no points and no tracks (the app keeps its activities). A way is divided into buckets of 10 m (``BucketCount``) and,
/// per bucket, month and category, the store counts the **activities** (once each, however often it passed) and the **passes** (every
/// traversal). The counts are derived from the legs: they are written in the same transaction as the legs and ``rebuildCounts()``
/// makes them again. The category is part of the key, so categories are kept apart and a combination is a sum of them.
///
/// The database is a SQLite file in the app's own folder, with write-ahead logging. It is not shared and nothing in it leaves the
/// device unless the app sends it (question 64, privacy). An activity is added or removed in one transaction, so an interrupted change
/// leaves the store as it was.
public actor TrackStore {
    /// The version of the layout of the database (`user_version`). A database with a higher number is refused.
    public static let version = 3

    private let database: SQLiteDatabase
    /// How the off-track lines are put together into traces. They are kept in the file: a store opened with other rules than the ones the
    /// traces were made with makes the traces again.
    public nonisolated let traceRules: TraceRules

    /// Opens a database, or makes one.
    ///
    /// One store is expected per file: a second connection to the same file waits up to 2 s for a change in progress and then fails
    /// with ``TrackStoreError/sqlite(_:)``.
    ///
    /// - Parameters:
    ///   - url: The file; its folder must exist. `nil` makes a database in memory that is gone when the store is.
    ///   - traceRules: How off-track lines are put together. They are kept in the file; opening it with other rules makes the traces again
    ///     the next time they are asked for.
    /// - Throws: ``TrackStoreError``.
    public init(url: URL?, traceRules: TraceRules = .standard) throws {
        let database = try SQLiteDatabase(path: url?.path ?? ":memory:")
        try Self.prepare(database, wal: url != nil)
        try Self.keep(traceRules, in: database)
        self.database = database
        self.traceRules = traceRules
    }

    /// Writes the rules of the traces into the file; if they are not the ones that the traces were made with, the traces are stale.
    private static func keep(_ rules: TraceRules, in database: SQLiteDatabase) throws {
        let text = String(decoding: try JSONEncoder().encode(rules), as: UTF8.self)
        var stored: String?
        try database.run("SELECT value FROM meta WHERE key = 'trace_rules'") { stored = $0.text(0) }
        guard stored != text else { return }
        try database.transaction {
            try database.execute("INSERT OR REPLACE INTO meta(key, value) VALUES ('trace_rules', ?)", [.text(text)])
            try database.execute("UPDATE meta SET value = '1' WHERE key = 'traces_stale'")
        }
    }

    /// Makes the tables of a new database and refuses one of a newer version.
    private static func prepare(_ database: SQLiteDatabase, wal: Bool) throws {
        try database.execute("PRAGMA foreign_keys = ON")
        if wal { try database.run("PRAGMA journal_mode = WAL") { _ in } }
        var found = 0
        try database.run("PRAGMA user_version") { found = Int($0.integer(0)) }
        guard found <= version else { throw TrackStoreError.newerVersion(found: found, supported: version) }
        if found < 1 {
            try database.transaction {
                try database.execute(
                    """
                    CREATE TABLE activity(
                        id INTEGER PRIMARY KEY, app_id TEXT NOT NULL UNIQUE, started REAL NOT NULL, month INTEGER NOT NULL,
                        category TEXT NOT NULL, tags BLOB NOT NULL, map_id TEXT NOT NULL, matched_with INTEGER NOT NULL)
                    """)
                try database.execute(
                    """
                    CREATE TABLE leg(
                        activity INTEGER NOT NULL REFERENCES activity(id) ON DELETE CASCADE, seq INTEGER NOT NULL, way INTEGER NOT NULL,
                        class INTEGER NOT NULL, from_metre INTEGER NOT NULL, to_metre INTEGER NOT NULL, direction INTEGER NOT NULL,
                        started_at REAL NOT NULL, elapsed REAL NOT NULL, profile BLOB NOT NULL, confidence REAL NOT NULL,
                        PRIMARY KEY(activity, seq)) WITHOUT ROWID
                    """)
                try database.execute("CREATE INDEX leg_way ON leg(way, from_metre)")
                try database.execute(
                    """
                    CREATE TABLE count(
                        way INTEGER NOT NULL, bucket INTEGER NOT NULL, month INTEGER NOT NULL, category TEXT NOT NULL,
                        activities INTEGER NOT NULL, passes INTEGER NOT NULL, PRIMARY KEY(way, bucket, month, category)) WITHOUT ROWID
                    """)
                // Version 1 is complete here, so a file that is not finished with version 2 can be opened again.
                try database.execute("PRAGMA user_version = 1")
            }
        }
        if found < 2 {
            try database.transaction {
                try database.execute(
                    "CREATE TABLE offtrack(id INTEGER PRIMARY KEY AUTOINCREMENT, activity INTEGER NOT NULL REFERENCES activity(id) ON DELETE CASCADE, "
                        + "seq INTEGER NOT NULL, started_at REAL NOT NULL, elapsed REAL NOT NULL, length REAL NOT NULL, line BLOB NOT NULL)")
                try database.execute("CREATE INDEX offtrack_activity ON offtrack(activity)")
                try database.execute("CREATE TABLE trace(id INTEGER PRIMARY KEY, line BLOB NOT NULL, length REAL NOT NULL)")
                try database.execute(
                    "CREATE TABLE trace_pass(trace INTEGER NOT NULL REFERENCES trace(id) ON DELETE CASCADE, "
                        + "offtrack INTEGER NOT NULL REFERENCES offtrack(id) ON DELETE CASCADE)")
                try database.execute("CREATE INDEX trace_pass_trace ON trace_pass(trace)")
                try database.execute("CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
                // The traces are derived from the off-track lines; there are none yet, so they are current.
                try database.execute("INSERT INTO meta(key, value) VALUES ('traces_stale', '0')")
                try database.execute("PRAGMA user_version = 2")
            }
        }
        if found < 3 {
            // Version 3 makes the traces of each category apart (see ``rebuildTraces()``); the ones that are there were made from all
            // categories together, so they are made again when they are next asked for.
            try database.transaction {
                try database.execute("UPDATE meta SET value = '1' WHERE key = 'traces_stale'")
                try database.execute("PRAGMA user_version = 3")
            }
        }
    }

    // MARK: Changing

    /// Adds an activity with its legs, in one transaction, and counts its buckets.
    ///
    /// An activity with the same ``StoredActivity/appID`` is replaced (its legs and its counts are taken out first). A leg whose range
    /// rounds to less than one bucket is left out as noise. **Rounding:** each end of a leg is rounded to the nearest 10 m, so a bucket
    /// counts when the leg covers more than half of it at an end (a leg from 141 to 144 m is dropped as noise, one from 143 to 148 m counts the whole
    /// bucket from 140 to 150 m), and a bucket moves by at most 5 m at each end.
    ///
    /// - Parameters:
    ///   - activity: The activity.
    ///   - legs: Its legs, in the order of travel; see ``TrackLegs``.
    ///   - offTrack: Its off-track stretches (see ``OffTrackLines``); the traces are made from them when they are asked for.
    /// - Returns: The number of legs that were kept.
    /// - Throws: ``TrackStoreError``; nothing is changed then.
    @discardableResult
    public func add(_ activity: StoredActivity, legs: [TrackLeg], offTrack: [OffTrackLine] = []) throws -> Int {
        let stored = legs.compactMap(StoredLeg.init)
        let tags = try JSONEncoder().encode(activity.tags)
        return try database.transaction {
            try removeActivity(appID: activity.appID)
            try database.execute(
                "INSERT INTO activity(app_id, started, month, category, tags, map_id, matched_with) VALUES (?, ?, ?, ?, ?, ?, ?)",
                [
                    .text(activity.appID), .real(activity.started.timeIntervalSince1970), .integer(Int64(activity.month.index)),
                    .text(activity.category), .blob(tags), .text(activity.mapID), .integer(Int64(activity.matchedWith)),
                ])
            var id: Int64 = 0
            try database.run("SELECT last_insert_rowid()") { id = $0.integer(0) }
            for (sequence, entry) in stored.enumerated() {
                try database.execute(
                    "INSERT INTO leg(activity, seq, way, class, from_metre, to_metre, direction, started_at, elapsed, profile, confidence) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    [
                        .integer(id), .integer(Int64(sequence)), .integer(entry.leg.wayID), .integer(Int64(entry.leg.classID)),
                        .integer(Int64(entry.fromMetre)), .integer(Int64(entry.toMetre)),
                        .integer(entry.leg.direction == .forward ? 1 : -1), .real(entry.leg.start.timeIntervalSince1970),
                        .real(entry.leg.elapsed), .blob(entry.profile), .real(entry.leg.confidence),
                    ])
            }
            try changeCounts(activity: id, by: 1)
            for (sequence, line) in offTrack.enumerated() {
                try database.execute(
                    "INSERT INTO offtrack(activity, seq, started_at, elapsed, length, line) VALUES (?, ?, ?, ?, ?, ?)",
                    [
                        .integer(id), .integer(Int64(sequence)), .real(line.start.timeIntervalSince1970), .real(line.elapsed), .real(line.length),
                        .blob(LineBlob.encode(line.coordinates)),
                    ])
            }
            if !offTrack.isEmpty { try setTracesStale() }
            return stored.count
        }
    }

    /// Removes an activity, its legs and its part of the counts, in one transaction.
    ///
    /// - Parameter appID: The id the app gave it.
    /// - Returns: Whether the store had it.
    /// - Throws: ``TrackStoreError``.
    @discardableResult
    public func remove(appID: String) throws -> Bool {
        try database.transaction { try removeActivity(appID: appID) }
    }

    /// Makes the counts again from the legs.
    ///
    /// The counts are derived, so this is for a repair or after a change of the counting rules. It is one transaction.
    ///
    /// - Throws: ``TrackStoreError``.
    public func rebuildCounts() throws {
        try database.transaction {
            try database.execute("DELETE FROM count")
            var ids: [Int64] = []
            try database.run("SELECT id FROM activity") { ids.append($0.integer(0)) }
            for id in ids { try changeCounts(activity: id, by: 1) }
        }
    }

    private func removeActivity(appID: String) throws -> Bool {
        var id: Int64?
        try database.run("SELECT id FROM activity WHERE app_id = ?", [.text(appID)]) { id = $0.integer(0) }
        guard let id else { return false }
        var hadOffTrack = false
        try database.run("SELECT 1 FROM offtrack WHERE activity = ? LIMIT 1", [.integer(id)]) { _ in hadOffTrack = true }
        if hadOffTrack { try setTracesStale() }
        try changeCounts(activity: id, by: -1)
        try database.execute("DELETE FROM activity WHERE id = ?", [.integer(id)])
        return true
    }

    /// Adds (`1`) or takes away (`-1`) the part of an activity in the counts.
    private func changeCounts(activity id: Int64, by sign: Int64) throws {
        var month: Int64 = 0
        var category = ""
        try database.run("SELECT month, category FROM activity WHERE id = ?", [.integer(id)]) {
            month = $0.integer(0)
            category = $0.text(1)
        }
        // Per bucket: the activity once, and one pass for each leg that covers it.
        var passes: [BucketKey: Int64] = [:]
        try database.run("SELECT way, from_metre, to_metre FROM leg WHERE activity = ?", [.integer(id)]) { row in
            let way = row.integer(0)
            for bucket in Int(row.integer(1) / 10)..<Int(row.integer(2) / 10) { passes[BucketKey(way: way, bucket: bucket), default: 0] += 1 }
        }
        for (key, count) in passes {
            try database.execute(
                """
                INSERT INTO count(way, bucket, month, category, activities, passes) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(way, bucket, month, category) DO UPDATE SET activities = activities + excluded.activities,
                    passes = passes + excluded.passes
                """,
                [.integer(key.way), .integer(Int64(key.bucket)), .integer(month), .text(category), .integer(sign), .integer(sign * count)])
        }
        if sign < 0 { try database.execute("DELETE FROM count WHERE activities <= 0 AND passes <= 0") }
    }

    // MARK: Traces

    private func setTracesStale() throws {
        try database.execute("UPDATE meta SET value = '1' WHERE key = 'traces_stale'")
    }

    /// Makes the traces again from the off-track lines, in the order of the activities' start times (see ``TraceBuilder``).
    ///
    /// **The traces of each category are made apart** (one ``TraceBuilder`` for each category). A line of one category never joins a
    /// trace of another, so the whole tracks of orienteering runs (which are kept as off-track lines, see `ImportMode.raw` of
    /// `TrackImport`) do not move the traces of trail runs. The cost is that a combination of categories shows the traces of each: two
    /// traces over the same ground are not merged into one.
    ///
    /// The traces are derived (by ``traceRules``), so this is for a repair. It is one transaction. ``traces(categories:months:)``
    /// does it by itself when an activity with off-track lines was added or removed since the last time.
    ///
    /// - Throws: ``TrackStoreError``.
    public func rebuildTraces() throws {
        try database.transaction {
            var builders: [String: TraceBuilder] = [:]
            var damaged: Int64?
            try database.run(
                "SELECT offtrack.id, offtrack.line, activity.category FROM offtrack JOIN activity ON activity.id = offtrack.activity "
                    + "ORDER BY activity.started, offtrack.id"
            ) { row in
                guard let line = LineBlob.decode(row.blob(1)) else {
                    damaged = row.integer(0)
                    return
                }
                builders[row.text(2), default: TraceBuilder(rules: traceRules)].add(line, source: row.integer(0))
            }
            if let damaged { throw TrackStoreError.damaged("the off-track line \(damaged)") }
            try database.execute("DELETE FROM trace_pass")
            try database.execute("DELETE FROM trace")
            // The id of a trace is made from the id of the line that started it, so the ids of different categories never meet.
            for trace in builders.values.flatMap(\.traces) {
                try database.execute(
                    "INSERT INTO trace(id, line, length) VALUES (?, ?, ?)",
                    [.integer(trace.id), .blob(LineBlob.encode(trace.coordinates)), .real(trace.length)])
                for source in trace.sources {
                    try database.execute("INSERT INTO trace_pass(trace, offtrack) VALUES (?, ?)", [.integer(trace.id), .integer(source)])
                }
            }
            try database.execute("UPDATE meta SET value = '0' WHERE key = 'traces_stale'")
        }
    }

    /// The traces, with how often each was run along by the activities of the categories and months asked for.
    ///
    /// The traces are made again first if an activity with off-track lines was added or removed since they were made. A trace that none
    /// of the activities asked for ran along is left out.
    ///
    /// - Parameters:
    ///   - categories: The categories to count, or `nil` for all.
    ///   - months: The months to count, or `nil` for all.
    /// - Returns: The traces in the order of their ids.
    /// - Throws: ``TrackStoreError``.
    public func traces(categories: Set<String>? = nil, months: ClosedRange<TrackMonth>? = nil) throws -> [StoredTrace] {
        var stale = false
        try database.run("SELECT value FROM meta WHERE key = 'traces_stale'") { stale = $0.text(0) != "0" }
        if stale { try rebuildTraces() }
        var sql =
            "SELECT trace.id, trace.line, trace.length, COUNT(*), COUNT(DISTINCT offtrack.activity) FROM trace_pass "
            + "JOIN trace ON trace.id = trace_pass.trace JOIN offtrack ON offtrack.id = trace_pass.offtrack "
            + "JOIN activity ON activity.id = offtrack.activity WHERE 1 = 1"
        var values: [SQLiteValue] = []
        if let months {
            sql += " AND activity.month BETWEEN ? AND ?"
            values += [.integer(Int64(months.lowerBound.index)), .integer(Int64(months.upperBound.index))]
        }
        if let categories {
            guard !categories.isEmpty else { return [] }
            let sorted = categories.sorted()
            sql += " AND activity.category IN (\(sorted.map { _ in "?" }.joined(separator: ",")))"
            values += sorted.map { .text($0) }
        }
        sql += " GROUP BY trace.id ORDER BY trace.id"
        var result: [StoredTrace] = []
        var damaged: Int64?
        try database.run(sql, values) { row in
            guard let line = LineBlob.decode(row.blob(1)) else {
                damaged = row.integer(0)
                return
            }
            result.append(
                StoredTrace(id: row.integer(0), coordinates: line, length: row.real(2), activities: Int(row.integer(4)), passes: Int(row.integer(3))))
        }
        if let damaged { throw TrackStoreError.damaged("the trace \(damaged)") }
        return result
    }

    /// How many activities each category has.
    ///
    /// - Returns: The activities by category; a category with none is not in it.
    /// - Throws: ``TrackStoreError``.
    public func activityCategories() throws -> [String: Int] {
        var result: [String: Int] = [:]
        try database.run("SELECT category, COUNT(*) FROM activity GROUP BY category") { result[$0.text(0)] = Int($0.integer(1)) }
        return result
    }

    /// The number of off-track lines in the store.
    public func offTrackLineCount() throws -> Int {
        var count = 0
        try database.run("SELECT COUNT(*) FROM offtrack") { count = Int($0.integer(0)) }
        return count
    }

    private struct BucketKey: Hashable {
        var way: Int64
        var bucket: Int
    }

    // MARK: Reading

    /// The counts of the buckets of some ways, added over the months and categories asked for.
    ///
    /// Each activity has one month and one category, so the counts of activities add up over them without counting an activity twice.
    ///
    /// - Parameters:
    ///   - ways: The OSM ids of the ways (for example those of a map area). Many ids are looked up in groups.
    ///   - categories: The categories to count, or `nil` for all. An empty set counts nothing. At most about 30,000 values (SQLite's limit
    ///     of variables in one statement).
    ///   - months: The months to count, or `nil` for all.
    /// - Returns: The buckets that were used at least once, in the order of way and bucket.
    /// - Throws: ``TrackStoreError``.
    public func counts(ways: [Int64], categories: Set<String>? = nil, months: ClosedRange<TrackMonth>? = nil) throws -> [BucketCount] {
        var result: [BucketCount] = []
        for group in stride(from: 0, to: ways.count, by: 500).map({ Array(ways[$0..<min($0 + 500, ways.count)]) }) {
            var sql = "SELECT way, bucket, SUM(activities), SUM(passes) FROM count WHERE way IN (\(group.map { _ in "?" }.joined(separator: ",")))"
            var values = group.map { SQLiteValue.integer($0) }
            if let months {
                sql += " AND month BETWEEN ? AND ?"
                values += [.integer(Int64(months.lowerBound.index)), .integer(Int64(months.upperBound.index))]
            }
            if let categories {
                guard !categories.isEmpty else { return [] }
                let sorted = categories.sorted()
                sql += " AND category IN (\(sorted.map { _ in "?" }.joined(separator: ",")))"
                values += sorted.map { .text($0) }
            }
            sql += " GROUP BY way, bucket ORDER BY way, bucket"
            try database.run(sql, values) {
                result.append(BucketCount(wayID: $0.integer(0), bucket: Int($0.integer(1)), activities: Int($0.integer(2)), passes: Int($0.integer(3))))
            }
        }
        return result.sorted { ($0.wayID, $0.bucket) < ($1.wayID, $1.bucket) }
    }

    /// The counts of the buckets of some ways for each month, for the categories asked for.
    ///
    /// The same counts as ``counts(ways:categories:months:)``, not added over the months: this is what a time-lapse is made from.
    ///
    /// - Parameters:
    ///   - ways: The OSM ids of the ways. Many ids are looked up in groups.
    ///   - categories: The categories to count, or `nil` for all. An empty set counts nothing.
    ///   - months: The months to count, or `nil` for all.
    /// - Returns: The buckets used at least once in a month, in the order of month, way and bucket.
    /// - Throws: ``TrackStoreError``.
    public func monthlyCounts(ways: [Int64], categories: Set<String>? = nil, months: ClosedRange<TrackMonth>? = nil) throws -> [MonthlyBucketCount] {
        var result: [MonthlyBucketCount] = []
        if let categories, categories.isEmpty { return [] }
        for group in stride(from: 0, to: ways.count, by: 500).map({ Array(ways[$0..<min($0 + 500, ways.count)]) }) {
            var sql =
                "SELECT way, bucket, month, SUM(activities), SUM(passes) FROM count WHERE way IN (\(group.map { _ in "?" }.joined(separator: ",")))"
            var values = group.map { SQLiteValue.integer($0) }
            if let months {
                sql += " AND month BETWEEN ? AND ?"
                values += [.integer(Int64(months.lowerBound.index)), .integer(Int64(months.upperBound.index))]
            }
            if let categories {
                let sorted = categories.sorted()
                sql += " AND category IN (\(sorted.map { _ in "?" }.joined(separator: ",")))"
                values += sorted.map { .text($0) }
            }
            sql += " GROUP BY way, bucket, month"
            try database.run(sql, values) {
                result.append(
                    MonthlyBucketCount(
                        month: TrackMonth(index: Int($0.integer(2))),
                        count: BucketCount(wayID: $0.integer(0), bucket: Int($0.integer(1)), activities: Int($0.integer(3)), passes: Int($0.integer(4)))))
            }
        }
        return result.sorted { ($0.month, $0.count.wayID, $0.count.bucket) < ($1.month, $1.count.wayID, $1.count.bucket) }
    }

    /// The first and the last month in which an activity started, or `nil` for an empty store.
    ///
    /// - Parameter categories: The categories to look at, or `nil` for all.
    public func activityMonths(categories: Set<String>? = nil) throws -> ClosedRange<TrackMonth>? {
        if let categories, categories.isEmpty { return nil }
        var sql = "SELECT MIN(month), MAX(month) FROM activity"
        var values: [SQLiteValue] = []
        if let categories {
            let sorted = categories.sorted()
            sql += " WHERE category IN (\(sorted.map { _ in "?" }.joined(separator: ",")))"
            values = sorted.map { .text($0) }
        }
        var found: (Int, Int)?
        try database.run(sql, values) { row in
            if row.isNull(0) { return }
            found = (Int(row.integer(0)), Int(row.integer(1)))
        }
        guard let found else { return nil }
        return TrackMonth(index: found.0)...TrackMonth(index: found.1)
    }

    /// The number of activities in the store.
    public func activityCount() throws -> Int {
        var count = 0
        try database.run("SELECT COUNT(*) FROM activity") { count = Int($0.integer(0)) }
        return count
    }

    /// The number of legs in the store.
    public func legCount() throws -> Int {
        var count = 0
        try database.run("SELECT COUNT(*) FROM leg") { count = Int($0.integer(0)) }
        return count
    }

    /// The tags and the record of an activity, or `nil` when the store does not have it.
    ///
    /// - Throws: ``TrackStoreError``, `damaged` when the tags cannot be read.
    public func activity(appID: String) throws -> StoredActivity? {
        var found: (Double, String, Data, String, Int)?
        try database.run("SELECT started, category, tags, map_id, matched_with FROM activity WHERE app_id = ?", [.text(appID)]) {
            found = ($0.real(0), $0.text(1), $0.blob(2), $0.text(3), Int($0.integer(4)))
        }
        guard let found else { return nil }
        guard let tags = try? JSONDecoder().decode([String: TagValue].self, from: found.2) else {
            throw TrackStoreError.damaged("the tags of the activity \(appID)")
        }
        return StoredActivity(
            appID: appID, started: Date(timeIntervalSince1970: found.0), category: found.1, tags: tags, mapID: found.3, matchedWith: found.4)
    }

    /// The seconds from the start of a leg to each 25 m along it, as stored, for the leg with this number of the activity.
    ///
    /// - Returns: `nil` when there is no such leg.
    public func timeProfile(appID: String, leg sequence: Int) throws -> [Float]? {
        var profile: Data?
        try database.run(
            "SELECT profile FROM leg JOIN activity ON activity.id = leg.activity WHERE app_id = ? AND seq = ?",
            [.text(appID), .integer(Int64(sequence))]
        ) { profile = $0.blob(0) }
        guard let profile else { return nil }
        return profile.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
