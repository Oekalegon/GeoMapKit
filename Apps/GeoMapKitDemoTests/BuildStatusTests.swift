import Foundation
import MapBuilder
import Regions
import Testing

@testable import GeoMapKitDemo

@Suite("Build status bar")
@MainActor
struct BuildStatusTests {
    private func summary(_ stage: MapBuildModel.Stage, download: Double? = nil, blocks: BlockProgress? = nil, levels: Int = 0) -> BuildStatusSummary {
        .make(stage: stage, downloadFraction: download, blocks: blocks, levelBlocksDone: levels)
    }

    @Test("Each stage has a title; the bar is determinate only where a fraction is known")
    func stages() {
        #expect(summary(.checking).title == "Checking the files" && summary(.checking).fraction == nil)
        let download = summary(.downloading, download: 0.4)
        #expect(download.title == "Downloading" && download.fraction == 0.4 && download.detail == "40 %")
        #expect(summary(.downloading).fraction == nil)
        #expect(summary(.buildingLevels, levels: 3).detail == "3 level blocks")
        #expect(summary(.registering).title == "Adding to the library")
    }

    @Test("The blocks show a percentage rounded down and the time left when it is known")
    func blocks() {
        let progress = BlockProgress(total: 8, finished: 3, running: 2, built: 3, elapsed: .seconds(60), remaining: .seconds(600))
        let made = summary(.buildingBlocks, blocks: progress)
        #expect(made.fraction == 0.375 && made.detail?.hasPrefix("37 %, about ") == true && made.detail?.hasSuffix(" left") == true)
        let early = BlockProgress(total: 8, finished: 0, running: 2, built: 0, elapsed: .seconds(5))
        #expect(summary(.buildingBlocks, blocks: early).detail == "0 %")
        #expect(summary(.buildingBlocks).fraction == nil)
    }

    @Test("A finished run shows no progress, and says how it ended")
    func ended() {
        let done = summary(.done(mapID: "m", name: "Greece"))
        #expect(done.hasEnded && done.title.contains("Greece"))
        #expect(summary(.cancelled).hasEnded && summary(.failed("x")).hasEnded && summary(.idle).hasEnded)
        #expect(!summary(.downloading).hasEnded)
    }

    @Test("A percentage never says 100 before the end and stays between 0 and 100")
    func percent() {
        #expect(BuildStatusSummary.percent(0.999) == "99 %")
        #expect(BuildStatusSummary.percent(1.5) == "100 %" && BuildStatusSummary.percent(-1) == "0 %")
    }

    // MARK: Host

    private let idleTools = MapBuildTools(
        buildBlocks: { _, _, _ in try await Task.sleep(for: .seconds(60)); throw CancellationError() },
        buildLevels: { _, _ in try await Task.sleep(for: .seconds(60)); throw CancellationError() })

    private func host(fails: Bool = false) -> (MapBuildHost, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-host-\(UUID().uuidString)", isDirectory: true)
        let tools = idleTools
        let host = MapBuildHost {
            if fails { throw URLError(.cannotCreateFile) }
            let picker = RegionPickerModel(
                catalog: FakeCatalog(), downloader: FakeNetwork(waits: true),
                cache: SourceCache(directory: folder, availableCapacity: { _ in 100_000_000_000 }))
            return MapBuildModel(picker: picker, catalog: FakeCatalog(), mapsRoot: folder.appendingPathComponent("Maps"), tools: tools, jobs: 1) { _, _ in "id" }
        }
        return (host, folder)
    }

    private func waitForDownloading(_ model: MapBuildModel) async {
        for _ in 0..<500 where model.stage != .downloading { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test("The picker opens, and not while a run is going or its result is still there; the model goes on when the picker closes")
    func openPicker() async throws {
        let (host, folder) = host()
        defer { try? FileManager.default.removeItem(at: folder) }
        host.openPicker()
        #expect(host.showsPicker && host.model != nil && !host.isBusy)
        let model = try #require(host.model)
        await model.picker.load()
        model.picker.setSelected("europe/netherlands", true)
        model.start()
        // Start closes the screen; the run is the host's and goes on.
        host.showsPicker = false
        await waitForDownloading(model)
        #expect(host.isBusy && host.isRunning && model.stage == .downloading)
        host.openPicker()
        #expect(!host.showsPicker)
        model.cancel()
        await model.waitForRun()
        // The result stays until it is dismissed.
        #expect(host.isBusy && !host.isRunning)
        host.openPicker()
        #expect(!host.showsPicker)
        model.dismissResult()
        host.openPicker()
        #expect(host.showsPicker)
    }

    @Test("A folder that cannot be used is reported and the picker stays closed")
    func openFails() {
        let (host, _) = host(fails: true)
        host.openPicker()
        #expect(!host.showsPicker && host.problem?.contains("source files") == true)
    }

    @Test("The download fraction is the bytes held over the sizes, and nil without sizes")
    func downloadFraction() async throws {
        let (host, folder) = host()
        defer { try? FileManager.default.removeItem(at: folder) }
        host.openPicker()
        let model = try #require(host.model)
        #expect(model.downloadFraction == nil)
        await model.picker.load()
        model.picker.setSelected("europe/netherlands", true)
        model.start()
        await waitForDownloading(model)
        for _ in 0..<500 where model.downloadFraction == nil || model.downloadFraction == 0 { try? await Task.sleep(for: .milliseconds(10)) }
        let fraction = try #require(model.downloadFraction)
        #expect(fraction > 0 && fraction <= 1)
        #expect(model.summary.title == "Downloading")
        model.cancel()
        await model.waitForRun()
    }
}
