import Foundation
import Observation
import Regions

/// The state of the screen where regions are chosen and their source files downloaded (question 63, step 2).
///
/// The flow is: the list of regions is loaded; the user selects regions; the plan is made (the sizes and the free space, nothing is
/// downloaded); the user goes on and the files are downloaded into the source cache, with progress and cancel. Nothing blocks on
/// size: a region is as big as it is, and the model only reports what it would take. The build of the maps from the files is a later
/// step. The model knows no platform, so a picker for the phone can use it later.
@MainActor
@Observable
final class RegionPickerModel: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }

    /// Where the list of regions is.
    enum ListState: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    /// Where the plan is.
    enum PlanState: Equatable {
        case none, planning
        case ready(DownloadPlan)
        case failed(String)
    }

    /// Where the download is.
    enum DownloadState: Equatable {
        case idle, downloading, cancelled, done
        case failed(String)
    }

    /// The free space wanted for each byte of source files, because the blocks and the levels are written next to them. A first
    /// estimate, to be replaced by a measured ratio.
    static let spaceFactor = 2.5

    private(set) var list: ListState = .idle
    private(set) var plan: PlanState = .none
    private(set) var download: DownloadState = .idle
    /// The bytes of each region's file that are held so far, and its size if known, while downloading.
    private(set) var progress: [String: (received: Int64, size: Int64?)] = [:]

    /// The whole tree of regions.
    private(set) var roots: [RegionNode] = []
    private var index: RegionIndex?

    /// The ids of the regions the user selected.
    private(set) var selection: Set<String> = []

    /// The text of the search field.
    var search = ""

    private let catalog: any RegionCatalog
    private let manager: SourceManager
    private let cache: SourceCache
    private var planTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - catalog: The list of regions.
    ///   - downloader: The network, for the files.
    ///   - cache: The source cache the files go to.
    init(catalog: any RegionCatalog, downloader: any Downloader, cache: SourceCache) {
        self.catalog = catalog
        manager = SourceManager(cache: cache, downloader: downloader)
        self.cache = cache
    }

    // MARK: List

    /// The tree as the search leaves it.
    var visibleRoots: [RegionNode] { roots.compactMap { $0.filtered(by: search) } }

    /// Loads the list of regions (the index is cached, and renewed when it is old). Does nothing while it is loading or loaded.
    func load() async {
        guard index == nil, list != .loading else { return }
        list = .loading
        do {
            let loaded = try await catalog.index()
            index = loaded
            roots = RegionNode.tree(of: loaded)
            list = .loaded
        } catch {
            list = .failed("The list of regions could not be loaded: \(error.localizedDescription)")
        }
    }

    // MARK: Selection

    func isSelected(_ id: String) -> Bool { selection.contains(id) }

    /// Selects or deselects a region. Any plan made before is dropped, because it no longer matches.
    func setSelected(_ id: String, _ on: Bool) {
        if on { selection.insert(id) } else { selection.remove(id) }
        planTask?.cancel()
        plan = .none
        if download != .downloading { download = .idle }
    }

    /// The selected regions that are to be downloaded: a region below a selected one is part of that one's file and is left out.
    var effectiveRegions: [SourceRegion] {
        guard let index else { return [] }
        return selection.compactMap { index.region(withID: $0) }
            .filter { region in !selection.contains { $0 != region.id && index.region(region.id, isBelow: $0) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The selected regions that are not downloaded because a region above them is selected.
    var coveredSelections: [SourceRegion] {
        guard let index else { return [] }
        let effective = Set(effectiveRegions.map(\.id))
        return selection.subtracting(effective).compactMap { index.region(withID: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Plan

    /// Makes the plan for the selection: asks the server for the size of each file that is not held and downloads nothing.
    func makePlan() async {
        let regions = effectiveRegions
        guard !regions.isEmpty else { return }
        planTask?.cancel()
        plan = .planning
        let task = Task { [manager] in
            do {
                let made = try await manager.plan(for: RegionSelection(regions: regions, coveredShare: 1))
                guard !Task.isCancelled else { return }
                self.plan = .ready(made)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                self.plan = .failed("The sizes could not be asked: \(error.localizedDescription)")
            }
        }
        planTask = task
        await task.value
    }

    /// The free space on the volume of the source cache, in bytes, or `nil` if the system does not say.
    var availableBytes: Int64? { cache.availableBytes() }

    /// A sentence about the free space for a plan, or `nil` when there is plenty. The sentence only informs.
    func spaceNote(for plan: DownloadPlan) -> String? {
        guard let available = availableBytes else { return nil }
        let download = plan.bytesToDownload
        if download > 0, available < download + SourceManager.spareBytes {
            return "There is not enough free space for the download (\(Self.size(download)) needed, \(Self.size(available)) free); it will be refused."
        }
        let total = plan.items.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
        let wanted = Int64(Double(total) * Self.spaceFactor)
        if total > 0, available < wanted {
            return "The maps made from these files need about \(Self.size(wanted)) in all; \(Self.size(available)) is free."
        }
        return nil
    }

    // MARK: Download

    /// Downloads the files of the plan that is ready, with progress; a download that was cancelled or stopped goes on after the
    /// bytes it holds when it is started again.
    func startDownload() {
        guard case .ready(let plan) = plan, download != .downloading else { return }
        download = .downloading
        progress = [:]
        downloadTask = Task { [manager] in
            do {
                _ = try await manager.fetch(plan) { id, received, size in
                    Task { @MainActor in self.record(id, received, size) }
                }
                self.download = .done
                // The files are held now: the plan is made again, so that it shows them as held.
                self.plan = .none
            } catch is CancellationError {
                self.download = .cancelled
            } catch {
                self.download = .failed("\(error)")
            }
        }
    }

    private func record(_ id: String, _ received: Int64, _ size: Int64?) {
        guard download == .downloading else { return }
        progress[id] = (max(received, progress[id]?.received ?? 0), size)
    }

    /// Stops the download. The part of the file that arrived is kept for the next start.
    func cancelDownload() { downloadTask?.cancel() }

    /// Waits until the download has ended (for tests).
    func waitForDownload() async { await downloadTask?.value }

    // MARK: Text

    /// A size in bytes with the units and the dot of the tools, whatever the language of the system.
    static func size(_ bytes: Int64) -> String {
        let value = Double(bytes)
        if value >= 1e9 { return String(format: "%.1f GB", value / 1e9) }
        if value >= 1e6 { return String(format: "%.1f MB", value / 1e6) }
        return String(format: "%.0f kB", value / 1e3)
    }
}
