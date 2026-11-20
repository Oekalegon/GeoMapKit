import Foundation
import GeoCore
import TrackMatching
import TrackStorage
import Tracks

/// Imports many files or recordings into a store: reads each, decides its category, skips what is in the store already, matches the rest
/// and adds it, with progress and cancellation.
///
/// The categories come in this order: a ``CategoryChange`` that picks the activity; the category the store has for it already (the
/// choice of the user is kept when a file is read again); the ``CategoryPolicy``. An activity that is in the store with the same
/// category, map and rules is skipped, so a run can be repeated, or continued after it was stopped, at the cost of reading the files.
///
/// "The same rules" is the number ``matchedWith``: when the app changes the cleaning or matching rules or the thresholds, it raises that
/// number, or nothing is made again.
public struct ActivityBatchImporter: Sendable {
    /// The networks of the map.
    public let networks: ActivityNetworks
    /// The store.
    public let store: TrackStore
    /// A name or identity of the map, stored with each activity.
    public var mapID: String
    /// How categories are chosen.
    public var policy: CategoryPolicy
    /// How points are cleaned.
    public var cleaning: TrackCleaningRules
    /// How points are matched.
    public var matching: MatchingRules
    /// The least confidence of a stretch that counts.
    public var minimumConfidence: Double
    /// The shortest stretch that counts, in metres.
    public var minimumStretchLength: Double
    /// The number stored as ``StoredActivity/matchedWith``; raise it when the rules change, and the activities are made again.
    public var matchedWith: Int
    /// How many requests are worked on at once (at least 1). Matching is the cost; the store adds one at a time.
    public var jobs: Int

    /// Creates an importer.
    public init(
        networks: ActivityNetworks, store: TrackStore, mapID: String, policy: CategoryPolicy = CategoryPolicy(),
        cleaning: TrackCleaningRules = .standard, matching: MatchingRules = .standard, minimumConfidence: Double = 0.5,
        minimumStretchLength: Double = 100, matchedWith: Int = 1, jobs: Int = 2
    ) {
        self.networks = networks
        self.store = store
        self.mapID = mapID
        self.policy = policy
        self.cleaning = cleaning
        self.matching = matching
        self.minimumConfidence = minimumConfidence
        self.minimumStretchLength = minimumStretchLength
        self.matchedWith = matchedWith
        self.jobs = max(jobs, 1)
    }

    /// Runs the requests.
    ///
    /// Cancelling the task stops the run after the requests that are in progress; what was done stays in the store.
    ///
    /// - Parameters:
    ///   - requests: What to import.
    ///   - change: A category to set for the activities a selection picks (bulk tagging); they are made again if it differs.
    ///   - progress: Called after each request, from any thread.
    /// - Returns: What was done. A source that cannot be read or an activity that fails is in ``ImportReport/failures``; the run goes on.
    public func run(
        _ requests: [ImportRequest], change: CategoryChange? = nil, progress: (@Sendable (ImportProgress) -> Void)? = nil
    ) async -> ImportReport {
        await run(requests, change: change, addsNew: true, progress: progress)
    }

    /// Sets a category for the activities a selection picks, and adds nothing else.
    ///
    /// An activity that is not in the store yet is left alone (it counts as skipped), so tagging does not start a long run of matching
    /// for files that were never imported. The activities that are in the store and picked are made again in the new category; the
    /// others are not touched.
    ///
    /// - Parameters:
    ///   - requests: The files or recordings to look in; an app can leave out those that the selection cannot reach (by a date it knows).
    ///   - change: The selection and the category.
    ///   - progress: Called after each request.
    public func retag(
        _ requests: [ImportRequest], change: CategoryChange, progress: (@Sendable (ImportProgress) -> Void)? = nil
    ) async -> ImportReport {
        await run(requests, change: change, addsNew: false, progress: progress)
    }

    private func run(
        _ requests: [ImportRequest], change: CategoryChange?, addsNew: Bool, progress: (@Sendable (ImportProgress) -> Void)?
    ) async -> ImportReport {
        var report = ImportReport()
        let claims = Claims()
        var finished = 0
        await withTaskGroup(of: (String, ImportReport).self) { group in
            var next = 0
            func start() {
                guard next < requests.count, !Task.isCancelled else { return }
                let request = requests[next]
                next += 1
                group.addTask { (request.source, await self.handle(request, change: change, addsNew: addsNew, claims: claims)) }
            }
            for _ in 0..<min(jobs, requests.count) { start() }
            while let (source, part) = await group.next() {
                report.merge(part)
                finished += 1
                progress?(ImportProgress(finished: finished, total: requests.count, source: source))
                start()
            }
        }
        report.cancelled = report.cancelled || finished < requests.count || Task.isCancelled
        return report
    }

    private func handle(_ request: ImportRequest, change: CategoryChange?, addsNew: Bool, claims: Claims) async -> ImportReport {
        var report = ImportReport()
        let loaded: ImportRequest.Loaded
        do { loaded = try request.load() } catch {
            report.failures.append(ImportFailure(source: request.source, activityID: nil, message: error.localizedDescription))
            return report
        }
        for problem in loaded.problems { report.notActivities.append(ImportFailure(source: request.source, activityID: nil, message: problem)) }
        for activity in loaded.activities {
            if Task.isCancelled {
                report.cancelled = true
                break
            }
            do {
                // The same activity in two sources of one run (a copy of a file) is handled once.
                guard await claims.claim(activity.id) else {
                    report.skipped += 1
                    continue
                }
                let existing = try await store.activity(appID: activity.id)
                let category: String
                if let change, change.selection.contains(activity) {
                    category = change.category
                } else {
                    category = existing?.category ?? policy.category(for: activity)
                }
                if existing == nil && !addsNew {
                    report.skipped += 1
                } else if let existing, existing.category == category, existing.mapID == mapID, existing.matchedWith == matchedWith {
                    report.skipped += 1
                } else {
                    try await add(activity, category: category)
                    if existing == nil { report.added += 1 } else { report.replaced += 1 }
                }
                if existing != nil || addsNew { report.categories[category, default: 0] += 1 }
            } catch {
                report.failures.append(ImportFailure(source: request.source, activityID: activity.id, message: error.localizedDescription))
            }
        }
        return report
    }

    private func add(_ activity: ActivityTrack, category: String) async throws {
        let mode = policy.mode(of: category)
        // A raw activity is not laid on lines, so it needs no network and the map is not read for it.
        let network = mode == .raw ? LineNetwork(features: []) : try await networks.network(for: Self.box(of: activity))
        let importer = ActivityImporter(
            network: network, mapID: mapID, cleaning: cleaning, matching: matching, minimumConfidence: minimumConfidence,
            minimumStretchLength: minimumStretchLength, matchedWith: matchedWith)
        try await importer.add(activity, category: category, mode: mode, to: store)
    }

    private static func box(of activity: ActivityTrack) -> BoundingBox {
        var south = Double.infinity, west = Double.infinity, north = -Double.infinity, east = -Double.infinity
        for point in activity.points {
            south = min(south, point.coordinate.latitude)
            north = max(north, point.coordinate.latitude)
            west = min(west, point.coordinate.longitude)
            east = max(east, point.coordinate.longitude)
        }
        return BoundingBox(south: south, west: west, north: north, east: east)
    }
}

/// The ids of the activities that a run has taken up, so that two sources with the same activity do not both add it.
private actor Claims {
    private var ids = Set<String>()
    func claim(_ id: String) -> Bool { ids.insert(id).inserted }
}

extension ImportReport {
    fileprivate mutating func merge(_ other: ImportReport) {
        added += other.added
        replaced += other.replaced
        skipped += other.skipped
        for (key, value) in other.categories { categories[key, default: 0] += value }
        failures += other.failures
        notActivities += other.notActivities
        cancelled = cancelled || other.cancelled
    }
}
