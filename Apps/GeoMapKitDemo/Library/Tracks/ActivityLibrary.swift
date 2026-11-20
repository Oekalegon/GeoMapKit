import FeatureStore
import Foundation
import GeoCore
import Observation
import TrackImport
import TrackStorage

/// The activities the user has put into the segment database: the store file, a run that imports GPX files into it, and what it holds.
///
/// All that is not the app's own is in the package: `ActivityBatchImporter` does the reading, the choice of category, the matching and
/// the adding; this class holds the state a screen shows (progress, the report) and starts and stops the run.
@MainActor
@Observable
final class ActivityLibrary {
    /// What the store holds.
    struct Totals: Equatable {
        var activities = 0
        var legs = 0
        var offTrackLines = 0
        var categories: [String: Int] = [:]
    }

    /// The numbers of the store, from the last time they were read.
    private(set) var totals = Totals()
    /// How far the run is, while there is one.
    private(set) var progress: ImportProgress?
    /// What the last run did.
    private(set) var report: ImportReport?
    /// Why the store or a run could not be used.
    private(set) var problem: String?

    /// The store file.
    let url: URL
    private var store: TrackStore?
    private var task: Task<Void, Never>?

    /// Opens the store in a folder: the Documents of the app, or another folder (tests use a new one).
    init(root: URL = URL.documentsDirectory) {
        url = root.appendingPathComponent("Activities.sqlite")
        do { store = try TrackStore(url: url) } catch { problem = "The activity store cannot be opened: \(error)" }
    }

    /// Whether a run is going.
    var isRunning: Bool { task != nil }

    /// Reads the numbers of the store.
    func refresh() async {
        guard let store else { return }
        do {
            totals = Totals(
                activities: try await store.activityCount(), legs: try await store.legCount(), offTrackLines: try await store.offTrackLineCount(),
                categories: try await store.activityCategories())
        } catch { problem = "\(error)" }
    }

    /// Imports GPX files into the store, with the map's lines.
    ///
    /// - Parameters:
    ///   - files: The files (the copies in the library of tracks).
    ///   - map: The map that the activities were recorded on.
    ///   - change: A category for the activities a selection picks (bulk tagging).
    func start(files: [URL], map: OpenedMap, change: CategoryChange? = nil) {
        guard task == nil, let store else { return }
        problem = nil
        report = nil
        progress = nil
        let batch = ActivityBatchImporter(networks: ActivityNetworks(source: map.source), store: store, mapID: map.id, jobs: 2)
        let requests = files.map { ImportRequest.gpx(at: $0) }
        task = Task {
            let result = await batch.run(requests, change: change) { progress in
                Task { @MainActor in self.progress = progress }
            }
            report = result
            progress = nil
            task = nil
            await refresh()
        }
    }

    /// Stops the run after the files that are being worked on; what was done stays.
    func cancel() { task?.cancel() }
}
