import Foundation
import MapBuilder
import Observation

/// Puts several maps of the library in one map: the merge, the sea between them, the levels and the entry in the library (question 65, step 2).
///
/// A run is stopped with ``cancel()`` and goes on with ``start()``: a merge that is done is not made again, and the levels that are built are
/// kept. The maps that are merged are not changed, unless the merge adds to one of them.
@MainActor
@Observable
final class MapMergeModel: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }

    /// Where the run is.
    enum Stage: Equatable {
        case idle
        /// The blocks are copied.
        case merging
        /// The sea between the maps is filled.
        case fillingSea
        case buildingLevels, registering
        /// The merged map is in the library under this id and name.
        case done(mapID: String, name: String)
        case cancelled
        case failed(String)
    }

    /// A map that is merged: its name and its folder.
    struct Input: Equatable {
        let name: String
        let folder: URL
    }

    /// The map that the merge makes.
    struct Output: Equatable {
        /// The folder of the map. A new map's folder does not exist yet; for a map that is added to, it is the folder of one of the inputs.
        let folder: URL
        /// The name in the library.
        let name: String
    }

    private(set) var stage: Stage = .idle
    /// The blocks written by the merge, and the blocks to write, while it runs.
    private(set) var written = 0
    private(set) var toWrite = 0
    /// The result of the merge, once it is done.
    private(set) var report: MapMergeReport?
    /// The progress of the level blocks, once they have begun.
    private(set) var levels: LevelProgress?
    /// Notes of the run, such as a sea that could not be filled.
    private(set) var notes: [String] = []

    let inputs: [Input]
    let output: Output
    private let tools: MapMergeTools
    private let jobs: Int
    private let register: @MainActor (URL, String) throws -> String
    private var task: Task<Void, Never>?
    private var mergeDone = false
    private var seaDone = false

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - inputs: The maps to merge; at least two (the map that is added to counts).
    ///   - output: The merged map. If its folder is one of the inputs, the others are added to that map.
    ///   - tools: The steps.
    ///   - jobs: How many level blocks are built at once.
    ///   - register: Puts the folder in the library under a name and returns the id of the map.
    init(
        inputs: [Input], output: Output, tools: MapMergeTools, jobs: Int = BlockRequest.recommendedJobs(),
        register: @escaping @MainActor (URL, String) throws -> String
    ) {
        self.inputs = inputs
        self.output = output
        self.tools = tools
        self.jobs = jobs
        self.register = register
    }

    /// Whether a stage is running.
    var isRunning: Bool {
        switch stage {
        case .merging, .fillingSea, .buildingLevels, .registering: true
        case .idle, .done, .cancelled, .failed: false
        }
    }

    /// The part done of the stage that has a number, or `nil`.
    var fraction: Double? {
        switch stage {
        case .merging: toWrite > 0 ? Double(written) / Double(toWrite) : nil
        case .buildingLevels: levels?.fraction
        default: nil
        }
    }

    /// Starts the run, or goes on with one that was stopped.
    func start() {
        guard !isRunning else { return }
        if case .done = stage { return }
        // A run that goes on keeps the notes it has: the merge is not made again, so they would not come back.
        if stage == .idle { notes = [] }
        stage = .merging
        task = Task { await run() }
    }

    /// Stops the run in whatever stage it is in. What was copied and built is kept.
    func cancel() { task?.cancel() }

    /// Waits until the run has ended (for tests).
    func waitForRun() async { await task?.value }

    private func run() async {
        // The folders of the library are linked by bookmarks: the sandbox needs their access to be started.
        let accessed = (inputs.map(\.folder) + [output.folder.deletingLastPathComponent(), output.folder]).filter { $0.startAccessingSecurityScopedResource() }
        defer { for url in accessed { url.stopAccessingSecurityScopedResource() } }
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Merging maps")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        do {
            try Task.checkCancellation()
            if !mergeDone {
                stage = .merging
                written = 0
                toWrite = 0
                let request = MapMergeRequest(inputs: inputs.map(\.folder), output: output.folder)
                report = try await tools.merge(request) { done, total in Task { @MainActor in self.noteMerge(done, total) } }
                mergeDone = true
                notes += report?.warnings ?? []
            }
            try Task.checkCancellation()

            if !seaDone {
                stage = .fillingSea
                do {
                    _ = try await tools.fillSea(output.folder)
                    seaDone = true
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // The sea is a finish, not a need: a map without it opens, and `fill-sea` can be run later.
                    notes.append("The sea between the maps was not filled (\(error.localizedDescription)); run fill-sea later.")
                    seaDone = true
                }
            }
            try Task.checkCancellation()

            stage = .buildingLevels
            levels = nil
            _ = try await tools.buildLevels(LevelRequest(directory: output.folder, jobs: jobs)) { progress in
                Task { @MainActor in self.noteLevels(progress) }
            }
            try Task.checkCancellation()

            stage = .registering
            stage = .done(mapID: try register(output.folder, output.name), name: output.name)
        } catch is CancellationError {
            stage = .cancelled
        } catch {
            stage = .failed(error is MapBuilderError ? "\(error)" : error.localizedDescription)
        }
    }

    private func noteMerge(_ done: Int, _ total: Int) {
        guard stage == .merging, done >= written else { return }
        written = done
        toWrite = total
    }

    private func noteLevels(_ progress: LevelProgress) {
        guard stage == .buildingLevels, progress.finished >= (levels?.finished ?? 0) else { return }
        levels = progress
    }

    // MARK: Plan

    /// What a merge is asked to do, from the maps the user ticked.
    struct Plan: Equatable {
        let inputs: [Input]
        let output: Output
    }

    /// Why the maps and the choice make no plan, as a sentence for the user.
    struct PlanError: Error, Equatable, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Makes the plan: the inputs by the folders of the maps, with the map that is added to first, and the output.
    ///
    /// - Parameters:
    ///   - maps: The ticked maps, by name and id, at least two.
    ///   - addTo: The id of the map the others are added to, or `nil` for a new map.
    ///   - name: The name of a new map.
    ///   - root: The folder new maps go in, or `nil` when it is not known.
    ///   - folder: The folder a map of the library links to, or `nil` when its link cannot be resolved.
    /// - Throws: ``PlanError`` for fewer than two maps, a link that cannot be resolved, a name the library refuses or an unknown root.
    static func plan(
        maps: [(id: String, name: String)], addTo: String?, name: String, root: URL?, folder: (String) -> URL?
    ) throws -> Plan {
        guard maps.count >= 2 else { throw PlanError(message: "Tick at least two maps.") }
        var inputs: [Input] = []
        for map in maps {
            guard let url = folder(map.id) else { throw PlanError(message: "The link of \(map.name) cannot be resolved.") }
            inputs.append(Input(name: map.name, folder: url))
        }
        if let id = addTo, let target = maps.first(where: { $0.id == id }), let url = folder(id) {
            // The map that is added to is the first of the maps.
            if let at = inputs.firstIndex(where: { $0.folder == url }) { inputs.swapAt(0, at) }
            return Plan(inputs: inputs, output: Output(folder: url, name: target.name))
        }
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard MapLibrary.isValidName(wanted) else { throw PlanError(message: "“\(wanted)” cannot be the name of a map: it must not be empty, start with a dot or contain a slash or a colon.") }
        guard let root else { throw PlanError(message: "The folder for new maps is not known.") }
        return Plan(inputs: inputs, output: Output(folder: newFolder(named: wanted, in: root), name: wanted))
    }

    // MARK: Folders

    /// The folder for a new merged map: the name as a folder name in `root`, and a number after it while that is taken.
    static func newFolder(named name: String, in root: URL) -> URL {
        let slug = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespaces)
        var candidate = root.appendingPathComponent(slug.isEmpty ? "Merged map" : slug, isDirectory: true)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = root.appendingPathComponent("\(slug) \(number)", isDirectory: true)
            number += 1
        }
        return candidate
    }
}
