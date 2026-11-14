import FeatureStore
import Foundation
import GeoCore
import Regions
import Testing

@testable import GeoMapKitDemo
@testable import MapBuilder

@Suite("Map build")
@MainActor
struct MapBuildModelTests {
    /// What the fake builds were asked to do, in order.
    actor Calls {
        private(set) var list: [String] = []
        func add(_ call: String) { list.append(call) }
        /// The `rebuild` flag of each request, as "blocks true" or "levels false".
        private(set) var rebuilds: [String] = []
        func noteRebuild(_ stage: String, _ flag: Bool) { rebuilds.append("\(stage) \(flag)") }
    }

    /// What was put in the library.
    @MainActor final class Registered {
        var entries: [(folder: URL, name: String)] = []
        var fails = false
    }

    struct RegisterFailed: Error {}

    struct Rig {
        let build: MapBuildModel
        let picker: RegionPickerModel
        let calls: Calls
        let registered: Registered
        let root: URL
    }

    private func tools(
        _ calls: Calls, blocks: @escaping @Sendable (BlockRequest) async throws -> Void = { _ in },
        levels: @escaping @Sendable () async throws -> Void = {}
    ) -> MapBuildTools {
        MapBuildTools(
            buildBlocks: { request, _, progress in
                await calls.add("blocks \(request.output.lastPathComponent) jobs \(request.jobs)")
                await calls.noteRebuild("blocks", request.rebuild)
                progress(BlockProgress(total: 4, finished: 2, running: 1, built: 2, elapsed: .seconds(10), remaining: .seconds(10)))
                try await blocks(request)
                return BlockRunReport(
                    outcomes: [], manifestURL: request.output.appendingPathComponent("manifest.json"), totalTime: .seconds(1),
                    peakFootprint: nil, warnings: ["A source file is old."], openSea: nil)
            },
            buildLevels: { request, progress in
                await calls.add("levels \(request.directory.lastPathComponent)")
                await calls.noteRebuild("levels", request.rebuild)
                progress(LevelOutcome(topZoom: 9, x: 1, y: 2, status: .upToDate))
                try await levels()
                return LevelRunReport(
                    outcomes: [], summaries: [], manifestURL: request.directory.appendingPathComponent("manifest.json"),
                    totalTime: .seconds(1), peakFootprint: nil, openAreaChains: 0, areaEndsJoined: 0, areaEndsJoinedAlongBorder: 0,
                    areaChainsClosedBySmallGap: 0)
            })
    }

    private func rig(
        network: FakeNetwork = FakeNetwork(), blocks: @escaping @Sendable (BlockRequest) async throws -> Void = { _ in },
        levels: @escaping @Sendable () async throws -> Void = {}, select: [String] = ["europe/belgium"]
    ) async -> Rig {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-build-\(UUID().uuidString)", isDirectory: true)
        let cache = SourceCache(directory: root.appendingPathComponent("Sources"), availableCapacity: { _ in 100_000_000_000 })
        let picker = RegionPickerModel(catalog: FakeCatalog(), downloader: network, cache: cache)
        await picker.load()
        for id in select { picker.setSelected(id, true) }
        let calls = Calls()
        let registered = Registered()
        let build = MapBuildModel(
            picker: picker, catalog: FakeCatalog(), mapsRoot: root.appendingPathComponent("Maps"),
            tools: tools(calls, blocks: blocks, levels: levels), jobs: 2
        ) { folder, name in
            if registered.fails { throw RegisterFailed() }
            registered.entries.append((folder, name))
            return "map-\(registered.entries.count)"
        }
        return Rig(build: build, picker: picker, calls: calls, registered: registered, root: root)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<500 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    // MARK: Runs

    @Test("A run goes through download, blocks, levels and the library, and the map is named after the region")
    func fullRun() async {
        let r = await rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        await r.picker.askSizes()
        r.build.start()
        #expect(r.build.isRunning && r.picker.selectionLocked)
        await r.build.waitForRun()
        #expect(r.build.stage == .done(mapID: "map-1", name: "België"))
        #expect(await r.calls.list == ["blocks europe-belgium jobs 2", "levels europe-belgium"])
        #expect(r.registered.entries.map(\.name) == ["België"])
        #expect(r.registered.entries.first?.folder.lastPathComponent == "europe-belgium")
        #expect(r.build.downloadedFiles && r.build.warnings == ["A source file is old."])
        #expect(!r.picker.selectionLocked, "the selection is free again")
    }

    @Test("Held files are not downloaded again, and the same regions build into the same folder")
    func secondRunBuildsAgain() async {
        let r = await rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        r.build.start()
        await r.build.waitForRun()
        r.build.dismissResult()
        // A finished map clears the selection: the same region is ticked again.
        #expect(!r.picker.isSelected("europe/belgium"))
        r.picker.setSelected("europe/belgium", true)
        r.build.start()
        await r.build.waitForRun()
        #expect(!r.build.downloadedFiles, "the file is held")
        #expect(await r.calls.list == ["blocks europe-belgium jobs 2", "levels europe-belgium", "blocks europe-belgium jobs 2", "levels europe-belgium"])
        #expect(Set(r.registered.entries.map(\.folder)).count == 1)
    }

    @Test("Build again builds every block and level again from the files that are held, and downloads nothing")
    func buildAgain() async {
        let counter = DownloadCounter()
        let r = await rig(network: FakeNetwork(counter: counter))
        defer { try? FileManager.default.removeItem(at: r.root) }
        r.build.start()
        await r.build.waitForRun()
        r.build.dismissResult()
        r.picker.setSelected("europe/belgium", true)
        r.build.start(.buildAgain)
        await r.build.waitForRun()
        #expect(r.build.stage == .done(mapID: "map-2", name: "België"))
        #expect(await r.calls.rebuilds == ["blocks false", "levels false", "blocks true", "levels true"])
        #expect(!r.build.downloadedFiles)
        #expect(await counter.count == 1, "the file was downloaded once, by the first run")
    }

    @Test("Download again deletes the files that are held, downloads them again and builds everything again")
    func downloadAgain() async {
        let counter = DownloadCounter()
        let r = await rig(network: FakeNetwork(counter: counter))
        defer { try? FileManager.default.removeItem(at: r.root) }
        r.build.start()
        await r.build.waitForRun()
        r.build.dismissResult()
        r.picker.setSelected("europe/belgium", true)
        r.build.start(.downloadAgain)
        await r.build.waitForRun()
        #expect(r.build.stage == .done(mapID: "map-2", name: "België"))
        #expect(await counter.count == 2)
        #expect(r.build.downloadedFiles)
        #expect(await r.calls.rebuilds == ["blocks false", "levels false", "blocks true", "levels true"])
        #expect(Set(r.registered.entries.map(\.folder)).count == 1, "the same map is updated")
    }

    @Test("A failed download after the files were deleted ends the run, and Continue fetches them")
    func downloadAgainFails() async {
        let r = await rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        r.build.start()
        await r.build.waitForRun()
        r.build.dismissResult()
        r.picker.setSelected("europe/belgium", true)
        // The server is gone: the same cache with a network that fails.
        let cache = SourceCache(directory: r.root.appendingPathComponent("Sources"), availableCapacity: { _ in 100_000_000_000 })
        #expect(cache.status(ofRegionID: "europe/belgium").status != .missing)
        let failing = RegionPickerModel(catalog: FakeCatalog(), downloader: FakeNetwork(failsDownload: true), cache: cache)
        await failing.load()
        failing.setSelected("europe/belgium", true)
        let build = MapBuildModel(
            picker: failing, catalog: FakeCatalog(), mapsRoot: r.root.appendingPathComponent("Maps"), tools: tools(r.calls), jobs: 2
        ) { _, _ in "map" }
        build.start(.downloadAgain)
        await build.waitForRun()
        guard case .failed = build.stage else { Issue.record("not failed: \(build.stage)"); return }
        #expect(cache.status(ofRegionID: "europe/belgium").status == .missing, "the file was deleted before the download")
        #expect(await r.calls.rebuilds.count == 2, "no build after the failed download")
    }

    @Test("A rebuild that is stopped is remembered as unfinished through Continue, until a full rebuild is done")
    func rebuildPending() async {
        let r = await rig(blocks: { request in if request.rebuild { try await Task.sleep(for: .seconds(60)) } })
        defer { try? FileManager.default.removeItem(at: r.root) }
        r.build.start()
        await r.build.waitForRun()
        #expect(!r.build.rebuildPending)
        r.build.dismissResult()
        r.picker.setSelected("europe/belgium", true)
        r.build.start(.buildAgain)
        await waitUntil { r.build.stage == .buildingBlocks }
        r.build.cancel()
        await r.build.waitForRun()
        #expect(r.build.stage == .cancelled && r.build.rebuildPending)
    }

    @Test("Regions added to a map are built into its folder, and the map keeps its name")
    func addingToAMap() async {
        let r = await rig(select: [])
        defer { try? FileManager.default.removeItem(at: r.root) }
        let folder = r.root.appendingPathComponent("Maps/greece", isDirectory: true)
        r.build.setTarget(.init(folder: folder, name: "Greece"))
        r.picker.setSelected("europe/belgium", true)
        r.build.start()
        #expect(r.build.target == nil && r.build.runTarget?.name == "Greece")
        #expect(r.build.workingFolder == folder, "a delete of that map is refused while it is written")
        await r.build.waitForRun()
        #expect(r.build.stage == .done(mapID: "map-1", name: "Greece"))
        #expect(await r.calls.list == ["blocks greece jobs 2", "levels greece"])
        #expect(r.registered.entries.first?.folder == folder && r.registered.entries.first?.name == "Greece")
        #expect(r.build.workingFolder == nil)
        r.build.dismissResult()
        #expect(r.build.runTarget == nil, "the next run is a map of its own")
    }

    @Test("Continue after a cancel keeps the map that regions are added to, and a target is not set during a run")
    func addingToAMapSurvivesACancel() async {
        let r = await rig(blocks: { _ in try await Task.sleep(for: .seconds(60)) }, select: [])
        defer { try? FileManager.default.removeItem(at: r.root) }
        let folder = r.root.appendingPathComponent("Maps/greece", isDirectory: true)
        r.build.setTarget(.init(folder: folder, name: "Greece"))
        r.picker.setSelected("europe/belgium", true)
        r.build.start()
        r.build.setTarget(nil)
        r.build.setTarget(.init(folder: folder.appendingPathComponent("x"), name: "Other"))
        #expect(r.build.target == nil, "no target is taken while a run is going")
        await waitUntil { r.build.stage == .buildingBlocks }
        r.build.cancel()
        await r.build.waitForRun()
        #expect(r.build.stage == .cancelled && r.build.runTarget?.folder == folder)
        r.build.start()
        await waitUntil { r.build.stage == .buildingBlocks }
        #expect(r.build.workingFolder == folder)
        r.build.cancel()
        await r.build.waitForRun()
    }

    @Test("A new target starts from an empty selection, and the host sets it only when it is free")
    func theHostSetsTheTarget() async {
        let r = await rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        #expect(r.picker.isSelected("europe/belgium"), "left from an earlier visit")
        let host = MapBuildHost { r.build }
        let greece = MapBuildModel.Target(folder: r.root.appendingPathComponent("Maps/greece"), name: "Greece")
        host.openPicker(adding: greece)
        #expect(host.showsPicker && r.build.target == greece)
        #expect(!r.picker.isSelected("europe/belgium"), "nothing is ticked that was meant for another map")
        // Closing the picker without starting leaves no target, and no ticks for the next map.
        r.picker.setSelected("europe/belgium", true)
        r.build.setTarget(nil)
        #expect(r.build.target == nil && !r.picker.isSelected("europe/belgium"))
        // The same target again keeps what was ticked after it.
        host.showsPicker = false
        host.openPicker(adding: greece)
        r.picker.setSelected("europe/belgium", true)
        r.build.setTarget(greece)
        #expect(r.picker.isSelected("europe/belgium"))
        // A run that is going keeps its own target: the host does not change it.
        r.build.start()
        host.openPicker(adding: MapBuildModel.Target(folder: r.root.appendingPathComponent("Maps/other"), name: "Other"))
        #expect(r.build.target == nil && r.build.runTarget == greece)
        await r.build.waitForRun()
    }

    @Test("Closing the picker without starting drops the target")
    func closingThePickerDropsTheTarget() async {
        let r = await rig(select: [])
        defer { try? FileManager.default.removeItem(at: r.root) }
        r.build.setTarget(.init(folder: r.root, name: "Greece"))
        #expect(r.build.target != nil)
        r.build.setTarget(nil)
        #expect(r.build.target == nil)
    }

    @Test("A cancel in the blocks stage stops the run, keeps the files and puts nothing in the library")
    func cancelInBlocks() async {
        let r = await rig(blocks: { _ in try await Task.sleep(for: .seconds(60)) })
        defer { try? FileManager.default.removeItem(at: r.root) }
        r.build.start()
        await waitUntil { r.build.stage == .buildingBlocks && r.build.blocks != nil }
        #expect(r.build.blocks?.finished == 2)
        r.build.cancel()
        await r.build.waitForRun()
        #expect(r.build.stage == .cancelled)
        #expect(await r.calls.list == ["blocks europe-belgium jobs 2"], "the levels did not start")
        #expect(r.registered.entries.isEmpty && !r.picker.selectionLocked)
    }

    @Test("A cancel in the download keeps the bytes, and Continue finishes the run")
    func cancelInDownloadThenContinue() async {
        let r = await rig(network: FakeNetwork(waits: true))
        defer { try? FileManager.default.removeItem(at: r.root) }
        r.build.start()
        await waitUntil { !r.picker.progress.isEmpty }
        r.build.cancel()
        await r.build.waitForRun()
        #expect(r.build.stage == .cancelled)
        #expect(await r.calls.list.isEmpty)
        // The picker planned again and knows the bytes that arrived: the next start continues after them.
        guard case .ready(let plan) = r.picker.plan else { Issue.record("no plan after the cancel"); return }
        #expect(plan.items.first?.alreadyDownloaded == 1_000)
        r.build.start()
        await r.build.waitForRun()
        #expect(r.build.stage == .done(mapID: "map-1", name: "België"))
        #expect(await r.calls.list == ["blocks europe-belgium jobs 2", "levels europe-belgium"])
    }

    @Test("A download that fails ends the run before any build")
    func downloadFails() async {
        let r = await rig(network: FakeNetwork(failsDownload: true))
        defer { try? FileManager.default.removeItem(at: r.root) }
        r.build.start()
        await r.build.waitForRun()
        guard case .failed = r.build.stage else { Issue.record("not failed: \(r.build.stage)"); return }
        #expect(await r.calls.list.isEmpty && r.registered.entries.isEmpty)
    }

    @Test("Sizes that cannot be asked end the run with the reason")
    func planFails() async {
        let r = await rig(network: FakeNetwork(failsMetadata: true))
        defer { try? FileManager.default.removeItem(at: r.root) }
        r.build.start()
        await r.build.waitForRun()
        guard case .failed = r.build.stage else { Issue.record("not failed: \(r.build.stage)"); return }
        #expect(await r.calls.list.isEmpty)
    }

    @Test("A failed block build reads as its sentence and the levels do not start")
    func blocksFail() async {
        let r = await rig(blocks: { _ in throw MapBuilderError("Nothing was built: every block of this area is empty.") })
        defer { try? FileManager.default.removeItem(at: r.root) }
        r.build.start()
        await r.build.waitForRun()
        #expect(r.build.stage == .failed("Nothing was built: every block of this area is empty."))
        #expect(await r.calls.list == ["blocks europe-belgium jobs 2"] && r.registered.entries.isEmpty)
    }

    @Test("A failed level build leaves the map out of the library")
    func levelsFail() async {
        let r = await rig(levels: { throw MapBuilderError("The blocks hold no overview band.") })
        defer { try? FileManager.default.removeItem(at: r.root) }
        r.build.start()
        await r.build.waitForRun()
        #expect(r.build.stage == .failed("The blocks hold no overview band."))
        #expect(r.registered.entries.isEmpty)
    }

    @Test("A library that refuses the map ends the run with an error")
    func registerFails() async {
        let r = await rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        r.registered.fails = true
        r.build.start()
        await r.build.waitForRun()
        guard case .failed = r.build.stage else { Issue.record("not failed: \(r.build.stage)"); return }
    }

    @Test("The selection stays as it is while a build runs")
    func selectionLocked() async {
        let r = await rig(blocks: { _ in try await Task.sleep(for: .seconds(60)) })
        defer { try? FileManager.default.removeItem(at: r.root) }
        r.build.start()
        await waitUntil { r.build.stage == .buildingBlocks }
        r.picker.setSelected("africa", true)
        #expect(!r.picker.isSelected("africa"))
        r.build.cancel()
        await r.build.waitForRun()
        r.picker.setSelected("africa", true)
        #expect(r.picker.isSelected("africa"))
    }

    @Test("Nothing selected, nothing starts")
    func nothingSelected() async {
        let r = await rig(select: [])
        defer { try? FileManager.default.removeItem(at: r.root) }
        r.build.start()
        #expect(r.build.stage == .idle && !r.build.isRunning)
    }

    @Test("A cancel before the run began, or while the sizes are asked, stops it before any download")
    func cancelWhileChecking() async {
        let counter = DownloadCounter()
        let r = await rig(network: FakeNetwork(metadataWaits: true, counter: counter))
        defer { try? FileManager.default.removeItem(at: r.root) }
        r.build.start()
        #expect(r.build.stage == .checking)
        r.build.cancel()   // at once: the task has not begun
        await r.build.waitForRun()
        #expect(r.build.stage == .cancelled)
        #expect(await counter.count == 0)
        // Once more, with the question to the server under way.
        r.build.dismissResult()
        r.build.start()
        await waitUntil { r.picker.plan == .planning }
        r.build.cancel()
        await r.build.waitForRun()
        #expect(r.build.stage == .cancelled)
        #expect(await counter.count == 0, "no download started")
        #expect(await r.calls.list.isEmpty && r.registered.entries.isEmpty && !r.picker.selectionLocked)
    }

    @Test("A cancel in the levels stage keeps the blocks and puts nothing in the library")
    func cancelInLevels() async {
        let r = await rig(levels: { try await Task.sleep(for: .seconds(60)) })
        defer { try? FileManager.default.removeItem(at: r.root) }
        r.build.start()
        await waitUntil { r.build.stage == .buildingLevels && r.build.levelBlocksDone > 0 }
        r.build.cancel()
        await r.build.waitForRun()
        #expect(r.build.stage == .cancelled && r.registered.entries.isEmpty)
        #expect(await r.calls.list == ["blocks europe-belgium jobs 2", "levels europe-belgium"])
    }

    // MARK: Names

    @Test("The map is named after its regions")
    func names() {
        let nl = fakeRegion("europe/netherlands", "Netherlands", parent: nil)
        let be = fakeRegion("europe/belgium", "Belgium", parent: nil)
        let lu = fakeRegion("europe/luxembourg", "Luxembourg", parent: nil)
        #expect(MapBuildModel.mapName(for: []) == "Map")
        #expect(MapBuildModel.mapName(for: [nl]) == "Netherlands")
        #expect(MapBuildModel.mapName(for: [nl, be]) == "Netherlands and Belgium")
        #expect(MapBuildModel.mapName(for: [nl, be, lu]) == "Netherlands and 2 more")
        #expect(MapBuildModel.mapName(for: [fakeRegion("x", "A/B: C", parent: nil)]) == "A-B- C", "a name stays a file name")
    }

    @Test("The same regions give the same folder, in any order; a long list is cut and hashed")
    func folders() {
        let root = URL(fileURLWithPath: "/maps")
        #expect(MapBuildModel.folder(for: ["europe/netherlands", "europe/belgium"], in: root).lastPathComponent == "europe-belgium+europe-netherlands")
        #expect(MapBuildModel.folder(for: ["b", "a"], in: root) == MapBuildModel.folder(for: ["a", "b"], in: root))
        let many = (0..<40).map { "europe/region-\($0)" }
        let long = MapBuildModel.folder(for: many, in: root).lastPathComponent
        #expect(long.count <= 80 && long == MapBuildModel.folder(for: many.reversed(), in: root).lastPathComponent)
        #expect(long != MapBuildModel.folder(for: many + ["europe/other"], in: root).lastPathComponent)
    }

    @Test("Jobs follow the cores and the memory, with 8 GB left for the system and the open map")
    func jobs() {
        let gb: UInt64 = 1_000_000_000
        #expect(MapBuildModel.defaultJobs(cores: 12, memory: 64 * gb) == 4)
        #expect(MapBuildModel.defaultJobs(cores: 18, memory: 48 * gb) == 4, "the Mac of the measurement")
        #expect(MapBuildModel.defaultJobs(cores: 10, memory: 32 * gb) == 4)
        #expect(MapBuildModel.defaultJobs(cores: 10, memory: 24 * gb) == 4)
        #expect(MapBuildModel.defaultJobs(cores: 8, memory: 16 * gb) == 2, "16 GB: 8 GB are free after two blocks of about 3 GB")
        #expect(MapBuildModel.defaultJobs(cores: 8, memory: 8 * gb) == 1, "8 GB leave nothing for more than one block")
        #expect(MapBuildModel.defaultJobs(cores: 2, memory: 64 * gb) == 1)
        #expect(MapBuildModel.defaultJobs(cores: 1, memory: 1 * gb) == 1, "less memory than the margin is still one job")
    }

    // MARK: Real build

    /// One region with the outline of a box, for the real build.
    private struct BoxCatalog: RegionCatalog {
        let box: BoundingBox
        func index() async throws -> RegionIndex {
            let ring = [
                Coordinate(latitude: box.south, longitude: box.west), Coordinate(latitude: box.south, longitude: box.east),
                Coordinate(latitude: box.north, longitude: box.east), Coordinate(latitude: box.north, longitude: box.west),
            ]
            return try RegionIndex(regions: [SourceRegion(
                id: "europe/small", name: "Small", parentID: nil, pbfURL: URL(string: "https://download.example.org/small.osm.pbf")!,
                outline: [RegionPolygon(outer: ring)])])
        }
    }

    /// Runs the real `MapBuilder` over a small PBF file given by `GEOMAPKIT_E2E_PBF` (for example Andorra, 3.5 MB) and checks the map
    /// that arrives in a library. Without the variable the test is skipped: it needs a real extract, which is not in the repository.
    @Test(
        "The real builds make a map that the library opens",
        .enabled(if: ProcessInfo.processInfo.environment["GEOMAPKIT_E2E_PBF"] != nil))
    func realBuild() async throws {
        let source = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["GEOMAPKIT_E2E_PBF"]))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-e2e-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let box = BoundingBox(south: 42.3, west: 1.3, north: 42.8, east: 1.9)
        let catalog = BoxCatalog(box: box)
        // The file is put in a cache of its own, as a download would.
        let cache = SourceCache(directory: root.appendingPathComponent("Sources"))
        let data = try Data(contentsOf: source)
        let url = URL(string: "https://download.example.org/small.osm.pbf")!
        try data.write(to: try cache.preparePart(regionID: "europe/small", etag: "\"e\"", keepBytes: false))
        try cache.install(regionID: "europe/small", from: url, info: RemoteFileInfo(size: Int64(data.count), etag: "\"e\""))

        let library = MapLibrary(root: root.appendingPathComponent("library"), defaults: UserDefaults(suiteName: "geomapkit-e2e-\(UUID().uuidString)")!)
        let picker = RegionPickerModel(catalog: catalog, downloader: FakeNetwork(), cache: cache)
        await picker.load()
        picker.setSelected("europe/small", true)
        let build = MapBuildModel(
            picker: picker, catalog: catalog, mapsRoot: root.appendingPathComponent("Maps"), tools: .live
        ) { folder, name in try library.addBuilt(folder: folder, name: name) }
        build.start()
        await build.waitForRun()
        guard case .done(let id, let name) = build.stage else { Issue.record("not done: \(build.stage)"); return }
        #expect(name == "Small")
        let map = try #require(library.maps.first { $0.id == id })
        let opened = try library.open(map)
        let set = try #require(opened.source as? StoreSet)
        #expect(!set.manifest.blocks.isEmpty && !set.manifest.levels.isEmpty, "blocks and levels are in the manifest")
        #expect((build.blocks?.total ?? 0) > 0 && build.levelBlocksDone > 0)
    }
}
