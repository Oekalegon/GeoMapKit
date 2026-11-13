import Foundation
import MapBuilder
import Observation
import Regions

/// Gets maps from regions: the download, the blocks, the levels and the entry in the library (question 63, step 3b).
///
/// One run takes the regions that are selected in the picker and goes through the stages in order, with progress for each and a
/// cancel in every stage. A run that was cancelled or stopped by an error is started again with ``start()``: the bytes that were
/// downloaded are kept (the plan is made again, so the download continues after them) and the blocks that are built are skipped.
/// The same regions always build into the same folder, so a second run updates the map that is there and does not add another.
@MainActor
@Observable
final class MapBuildModel: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }

    /// Where the run is.
    enum Stage: Equatable {
        case idle
        /// The files are checked: the plan says what is held and what is missing.
        case checking
        case downloading, buildingBlocks, buildingLevels, registering
        /// The map is in the library under this id and name.
        case done(mapID: String, name: String)
        case cancelled
        case failed(String)
    }

    /// The picker: the list, the selection, the plan and the download.
    let picker: RegionPickerModel
    private(set) var stage: Stage = .idle
    /// The progress of the blocks, once the stage has begun.
    private(set) var blocks: BlockProgress?
    /// The level blocks that are done.
    private(set) var levelBlocksDone = 0
    /// Whether this run had files to download (otherwise the stage is shown as skipped).
    private(set) var downloadedFiles = false
    /// Notes of the build, such as a source file that is old.
    private(set) var warnings: [String] = []

    private let catalog: any RegionCatalog
    private let mapsRoot: URL
    private let tools: MapBuildTools
    private let register: @MainActor (URL, String) throws -> String
    private let jobs: Int
    private var task: Task<Void, Never>?

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - picker: The picker whose selection is built.
    ///   - catalog: The list of regions the blocks are planned from.
    ///   - mapsRoot: The folder the maps are built in: each set of regions gets a folder of its own.
    ///   - tools: The builds.
    ///   - jobs: How many blocks are built at once; by default from the cores and the memory of this Mac.
    ///   - register: Puts a built folder in the library under a name and returns the id of the map.
    init(
        picker: RegionPickerModel, catalog: any RegionCatalog, mapsRoot: URL, tools: MapBuildTools = .live,
        jobs: Int = MapBuildModel.defaultJobs(), register: @escaping @MainActor (URL, String) throws -> String
    ) {
        self.picker = picker
        self.catalog = catalog
        self.mapsRoot = mapsRoot
        self.tools = tools
        self.jobs = jobs
        self.register = register
    }

    /// Whether a stage is running.
    var isRunning: Bool {
        switch stage {
        case .checking, .downloading, .buildingBlocks, .buildingLevels, .registering: true
        case .idle, .done, .cancelled, .failed: false
        }
    }

    // MARK: Run

    /// Starts the run for the regions that are selected, or goes on with one that was stopped.
    func start() {
        guard !isRunning else { return }
        let regions = picker.effectiveRegions
        guard !regions.isEmpty else { return }
        picker.selectionLocked = true
        blocks = nil
        levelBlocksDone = 0
        downloadedFiles = false
        warnings = []
        stage = .checking
        task = Task { await run(regions) }
    }

    /// Stops the run in whatever stage it is in. What was downloaded and built is kept.
    func cancel() {
        guard isRunning else { return }
        // While the sizes are asked there is no download yet: the question to the server is what has to stop.
        if stage == .checking { picker.cancelPlan() } else { picker.cancelDownload() }
        task?.cancel()
    }

    /// Clears the end of a run (cancelled, failed or done), back to the picker.
    func dismissResult() {
        guard !isRunning else { return }
        stage = .idle
    }

    /// Waits until the run has ended (for tests).
    func waitForRun() async { await task?.value }

    private func run(_ regions: [SourceRegion]) async {
        // The Mac does not sleep, and the system does not slow this down, while a map is being built.
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Building a map")
        defer {
            ProcessInfo.processInfo.endActivity(activity)
            picker.selectionLocked = false
        }
        do {
            // A cancel that came before this task began must not start the question to the server.
            try Task.checkCancellation()
            // The plan says what is held and what is missing; after an earlier run it is made again here.
            if case .ready = picker.plan {} else { await picker.makePlan() }
            // A cancel while the sizes were asked must not go on to the download.
            try Task.checkCancellation()
            guard case .ready(let plan) = picker.plan else {
                if case .failed(let message) = picker.plan { stage = .failed(message) } else { stage = .cancelled }
                return
            }
            if plan.needsDownload {
                downloadedFiles = true
                stage = .downloading
                picker.startDownload()
                await picker.waitForDownload()
                switch picker.download {
                case .done: break
                case .cancelled: stage = .cancelled; return
                case .failed(let message): stage = .failed(message); return
                case .idle, .downloading: stage = .failed("The download did not finish."); return
                }
            }
            try Task.checkCancellation()

            let folder = Self.folder(for: regions.map(\.id), in: mapsRoot)
            try FileManager.default.createDirectory(at: mapsRoot, withIntermediateDirectories: true)
            stage = .buildingBlocks
            let request = BlockRequest(
                area: .regions(regions.map(\.id)), output: folder, jobs: jobs, cacheDirectory: picker.cacheDirectory)
            let report = try await tools.buildBlocks(request, catalog) { progress in
                Task { @MainActor in self.noteBlocks(progress) }
            }
            warnings = report.warnings
            try Task.checkCancellation()

            stage = .buildingLevels
            _ = try await tools.buildLevels(LevelRequest(directory: folder, jobs: jobs)) { _ in
                Task { @MainActor in self.noteLevelBlock() }
            }
            try Task.checkCancellation()

            stage = .registering
            let name = Self.mapName(for: regions)
            stage = .done(mapID: try register(folder, name), name: name)
        } catch is CancellationError {
            stage = .cancelled
        } catch {
            stage = .failed(Self.describe(error))
        }
    }

    private func noteBlocks(_ progress: BlockProgress) {
        guard stage == .buildingBlocks, progress.finished >= (blocks?.finished ?? 0) else { return }
        blocks = progress
    }

    private func noteLevelBlock() {
        guard stage == .buildingLevels else { return }
        levelBlocksDone += 1
    }

    // MARK: Names

    /// The name of the map in the library: one region by its name, two joined by "and", more as "first and N more".
    static func mapName(for regions: [SourceRegion]) -> String {
        let names = regions.map { $0.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") }
        switch names.count {
        case 0: return "Map"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names[0]) and \(names.count - 1) more"
        }
    }

    /// The folder for a set of regions: the same regions always give the same folder, whatever the order. A long list is cut and
    /// ended with a hash of the whole list.
    static func folder(for ids: [String], in root: URL) -> URL {
        let sorted = ids.sorted()
        var slug = sorted.map { $0.replacingOccurrences(of: "/", with: "-") }.joined(separator: "+")
        if slug.count > 80 {
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            for byte in sorted.joined(separator: "+").utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
            slug = String(slug.prefix(60)) + "-" + String(hash, radix: 16)
        }
        return root.appendingPathComponent(slug, isDirectory: true)
    }

    /// How many blocks to build at once: half the cores, at most 4 (as the command-line tool), and no more than the memory allows at
    /// 3 GB for each. That is a safety factor: a block takes about 0.75 GB and the run over Østlandet and Sweden peaked at 4.2 GB with
    /// 4 jobs, about 1 GB for each. The same number is used for the level blocks.
    nonisolated static func defaultJobs(
        cores: Int = ProcessInfo.processInfo.activeProcessorCount, memory: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> Int {
        max(1, min(cores / 2, 4, Int(memory / 3_000_000_000)))
    }

    private static func describe(_ error: Error) -> String {
        if error is MapBuilderError || error is SourceError { return "\(error)" }
        return error.localizedDescription
    }
}
