import Foundation
import GeoCore
import Regions
import Testing

@testable import GeoMapKitDemo

@Suite("Region picker")
@MainActor
struct RegionPickerModelTests {
    private nonisolated static let ring = [
        Coordinate(latitude: 50, longitude: 3), Coordinate(latitude: 50, longitude: 7),
        Coordinate(latitude: 54, longitude: 7), Coordinate(latitude: 54, longitude: 3),
    ]

    private nonisolated static func region(_ id: String, _ name: String, parent: String?) -> SourceRegion {
        SourceRegion(
            id: id, name: name, parentID: parent, pbfURL: URL(string: "https://download.example.org/\(id).osm.pbf")!,
            outline: [RegionPolygon(outer: ring)])
    }

    private struct Catalog: RegionCatalog {
        var fails = false
        func index() async throws -> RegionIndex {
            if fails { throw URLError(.notConnectedToInternet) }
            return try RegionIndex(regions: [
                region("europe", "Europe", parent: nil),
                region("europe/netherlands", "Netherlands", parent: "europe"),
                region("europe/netherlands/zuid-holland", "Zuid-Holland", parent: "europe/netherlands"),
                region("europe/netherlands/noord-brabant", "Noord-Brabant", parent: "europe/netherlands"),
                region("europe/belgium", "België", parent: "europe"),
                region("africa", "Africa", parent: nil),
            ])
        }
    }

    /// A network that serves files of a fixed size, or waits until the download is cancelled.
    private struct Network: Downloader {
        var size: Int64 = 3_000
        /// Waits for a cancel: after one chunk of a new file (a resumed file is completed).
        var waits = false
        var failsDownload = false
        var failsMetadata = false
        func metadata(of url: URL, ifNoneMatch etag: String?) async throws -> RemoteMetadata {
            if failsMetadata { throw URLError(.notConnectedToInternet) }
            return .info(RemoteFileInfo(size: size, etag: "\"e\""))
        }
        func download(
            from url: URL, to file: URL, resumeFrom offset: Int64, ifRange etag: String?, progress: @Sendable (Int64) -> Void
        ) async throws -> RemoteFileInfo {
            if failsDownload { throw URLError(.networkConnectionLost) }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            let chunk = Int(size) / 3
            if waits && offset == 0 {
                try handle.write(contentsOf: Data(count: chunk))
                progress(Int64(chunk))
                try await Task.sleep(for: .seconds(60))
            }
            while try Int64(handle.offset()) < size {
                try handle.write(contentsOf: Data(count: chunk))
                progress(try Int64(handle.offset()))
            }
            return RemoteFileInfo(size: size, etag: "\"e\"")
        }
    }

    private func make(
        catalog: Catalog = Catalog(), network: Network = Network(), free: Int64 = 100_000_000_000
    ) -> (model: RegionPickerModel, cache: SourceCache, folder: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-picker-\(UUID().uuidString)", isDirectory: true)
        let cache = SourceCache(directory: folder, availableCapacity: { _ in free })
        return (RegionPickerModel(catalog: catalog, downloader: network, cache: cache), cache, folder)
    }

    @Test("The list is a tree by name; a region whose parent is missing is a root")
    func tree() async {
        let (model, _, folder) = make()
        defer { try? FileManager.default.removeItem(at: folder) }
        await model.load()
        #expect(model.list == .loaded)
        #expect(model.roots.map(\.id) == ["africa", "europe"])
        let europe = model.roots[1]
        #expect(europe.children.map(\.id) == ["europe/belgium", "europe/netherlands"])
        #expect(europe.children[1].children.map(\.id) == ["europe/netherlands/noord-brabant", "europe/netherlands/zuid-holland"])
        #expect(europe.children[0].outlineChildren == nil)
    }

    @Test("The search keeps a match with what is below it, and the regions above it; case and accents do not matter")
    func search() async {
        let (model, _, folder) = make()
        defer { try? FileManager.default.removeItem(at: folder) }
        await model.load()
        model.search = "belgie"
        #expect(model.visibleRoots.map(\.id) == ["europe"])
        #expect(model.visibleRoots[0].children.map(\.id) == ["europe/belgium"])
        model.search = "NETHER"
        #expect(model.visibleRoots[0].children[0].children.count == 2, "a match keeps everything below it")
        model.search = "nowhere"
        #expect(model.visibleRoots.isEmpty)
        model.search = "  "
        #expect(model.visibleRoots.count == 2)
    }

    @Test("A region below a selected region is not downloaded on its own")
    func parentCoversChild() async {
        let (model, _, folder) = make()
        defer { try? FileManager.default.removeItem(at: folder) }
        await model.load()
        model.setSelected("europe/netherlands/zuid-holland", true)
        model.setSelected("europe/netherlands", true)
        model.setSelected("africa", true)
        #expect(model.effectiveRegions.map(\.id) == ["africa", "europe/netherlands"])
        #expect(model.coveredSelections.map(\.id) == ["europe/netherlands/zuid-holland"])
        model.setSelected("europe/netherlands", false)
        #expect(model.effectiveRegions.map(\.id) == ["africa", "europe/netherlands/zuid-holland"])
        #expect(model.coveredSelections.isEmpty)
    }

    @Test("The plan reports the sizes and goes away when the selection changes")
    func plan() async throws {
        let (model, _, folder) = make()
        defer { try? FileManager.default.removeItem(at: folder) }
        await model.load()
        model.setSelected("europe/belgium", true)
        model.setSelected("europe/netherlands", true)
        await model.makePlan()
        guard case .ready(let plan) = model.plan else { Issue.record("no plan: \(model.plan)"); return }
        #expect(plan.items.count == 2 && plan.bytesToDownload == 6_000 && plan.needsDownload)
        model.setSelected("africa", true)
        #expect(model.plan == .none)
    }

    @Test("Without a selection there is nothing to check")
    func emptySelection() async {
        let (model, _, folder) = make()
        defer { try? FileManager.default.removeItem(at: folder) }
        await model.load()
        await model.makePlan()
        #expect(model.plan == .none)
    }

    @Test("The note about space only informs: it names a download that will be refused and a map that will not fit")
    func spaceNote() {
        let wide = DownloadPlan(
            items: [PlanItem(region: Self.region("x", "X", parent: nil), action: .download, size: 1_000_000_000)], coveredShare: 1)
        let plenty = make(free: 100_000_000_000)
        defer { try? FileManager.default.removeItem(at: plenty.folder) }
        #expect(plenty.model.spaceNote(for: wide) == nil)
        let tight = make(free: 2_000_000_000)
        defer { try? FileManager.default.removeItem(at: tight.folder) }
        #expect(tight.model.spaceNote(for: wide)?.contains("need roughly 2.5 GB") == true)
        let none = make(free: 500_000_000)
        defer { try? FileManager.default.removeItem(at: none.folder) }
        #expect(none.model.spaceNote(for: wide)?.contains("will be refused") == true)
    }

    @Test("The download puts the files in the cache and reports progress")
    func downloads() async throws {
        let (model, cache, folder) = make()
        defer { try? FileManager.default.removeItem(at: folder) }
        await model.load()
        model.setSelected("europe/belgium", true)
        await model.makePlan()
        model.startDownload()
        #expect(model.download == .downloading)
        await model.waitForDownload()
        #expect(model.download == .done)
        #expect(cache.status(ofRegionID: "europe/belgium").0 != .missing)
        #expect(model.progress["europe/belgium"]?.received == 3_000)
        // The plan is made again from what is held now: nothing left to download.
        await model.makePlan()
        guard case .ready(let plan) = model.plan else { Issue.record("no plan"); return }
        #expect(!plan.needsDownload)
    }

    @Test("A download can be cancelled")
    func cancels() async {
        let (model, _, folder) = make(network: Network(waits: true))
        defer { try? FileManager.default.removeItem(at: folder) }
        await model.load()
        model.setSelected("europe/belgium", true)
        await model.makePlan()
        model.startDownload()
        model.cancelDownload()
        await model.waitForDownload()
        #expect(model.download == .cancelled)
    }

    @Test("A list that cannot be loaded says so")
    func loadFails() async {
        let (model, _, folder) = make(catalog: Catalog(fails: true))
        defer { try? FileManager.default.removeItem(at: folder) }
        await model.load()
        guard case .failed = model.list else { Issue.record("it did not fail"); return }
        #expect(model.roots.isEmpty)
    }

    /// Waits until the download has reported some bytes, so that a cancel comes after them.
    private func waitForBytes(_ model: RegionPickerModel) async {
        for _ in 0..<500 where model.progress.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test("A cancelled download is planned again, and the next start continues after the bytes that arrived")
    func resumes() async throws {
        let (model, cache, folder) = make(network: Network(waits: true))
        defer { try? FileManager.default.removeItem(at: folder) }
        await model.load()
        model.setSelected("europe/belgium", true)
        await model.makePlan()
        model.startDownload()
        await waitForBytes(model)
        model.cancelDownload()
        await model.waitForDownload()
        #expect(model.download == .cancelled)
        guard case .ready(let plan) = model.plan else { Issue.record("no plan after the cancel: \(model.plan)"); return }
        #expect(plan.items.first?.alreadyDownloaded == 1_000, "the plan knows the bytes that arrived")
        #expect(plan.bytesToDownload == 2_000)
        model.startDownload()
        await model.waitForDownload()
        #expect(model.download == .done)
        #expect(cache.status(ofRegionID: "europe/belgium").status != .missing)
        let size = cache.partialDownload(regionID: "europe/belgium")?.bytes ?? 0
        #expect(size == 0, "the part file became the file")
        #expect(model.progress["europe/belgium"]?.received == 3_000)
    }

    @Test("A failed download says so, and is planned again")
    func downloadFails() async {
        let (model, _, folder) = make(network: Network(failsDownload: true))
        defer { try? FileManager.default.removeItem(at: folder) }
        await model.load()
        model.setSelected("europe/belgium", true)
        await model.makePlan()
        model.startDownload()
        await model.waitForDownload()
        guard case .failed = model.download else { Issue.record("it did not fail: \(model.download)"); return }
        guard case .ready = model.plan else { Issue.record("no plan after the failure: \(model.plan)"); return }
    }

    @Test("Sizes that cannot be asked are reported, not a plan")
    func planFails() async {
        let (model, _, folder) = make(network: Network(failsMetadata: true))
        defer { try? FileManager.default.removeItem(at: folder) }
        await model.load()
        model.setSelected("europe/belgium", true)
        await model.makePlan()
        guard case .failed = model.plan else { Issue.record("it did not fail: \(model.plan)"); return }
    }

    @Test("The selection stays as it is while a download runs")
    func selectionLocked() async {
        let (model, _, folder) = make(network: Network(waits: true))
        defer { try? FileManager.default.removeItem(at: folder) }
        await model.load()
        model.setSelected("europe/belgium", true)
        await model.makePlan()
        model.startDownload()
        model.setSelected("africa", true)
        #expect(!model.isSelected("africa"))
        guard case .ready = model.plan else { Issue.record("the plan went away"); return }
        model.cancelDownload()
        await model.waitForDownload()
        model.setSelected("africa", true)
        #expect(model.isSelected("africa"))
    }

    @Test("The note says when the maps made from the files would not fit, though the download does")
    func spaceNoteMapsDoNotFit() {
        let plan = DownloadPlan(
            items: [PlanItem(region: Self.region("x", "X", parent: nil), action: .download, size: 1_000_000_000)], coveredShare: 1)
        let (model, _, folder) = make(free: 2_000_000_000)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(model.spaceNote(for: plan)?.contains("roughly 2.5 GB") == true)
        let done = DownloadPlan(
            items: [PlanItem(region: Self.region("x", "X", parent: nil), action: .useCached, size: 1_000_000_000)], coveredShare: 1)
        #expect(model.spaceNote(for: done)?.contains("roughly") == true, "files that are held still need room for the maps")
    }

    @Test("The plan can be dropped, and then there is nothing to start")
    func planDropped() async {
        let (model, _, folder) = make()
        defer { try? FileManager.default.removeItem(at: folder) }
        await model.load()
        model.setSelected("europe/belgium", true)
        await model.makePlan()
        model.cancelPlan()
        #expect(model.plan == .none && model.download == .idle)
        model.startDownload()
        #expect(model.download == .idle, "without a plan nothing starts")
        #expect(model.isSelected("europe/belgium"), "the selection stays")
    }
}
