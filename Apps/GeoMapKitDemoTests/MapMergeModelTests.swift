#if os(macOS)
import Foundation
import Testing

@testable import GeoMapKitDemo
@testable import MapBuilder

@Suite("Map merge")
@MainActor
struct MapMergeModelTests {
    actor Calls {
        private(set) var list: [String] = []
        func add(_ call: String) { list.append(call) }
    }

    struct Failed: Error {}

    private func report(blocks: Int = 5) -> MapMergeReport {
        MapMergeReport(blocks: blocks, written: 3, replaced: 0, overlaps: [], hasLevels: false, warnings: [], nextSteps: ["Run fill-sea on the merged map."])
    }

    private func tools(
        _ calls: Calls, merge: @escaping @Sendable () async throws -> Void = {}, sea: @escaping @Sendable () async throws -> Int = { 2 },
        levels: @escaping @Sendable () async throws -> Void = {}
    ) -> MapMergeTools {
        MapMergeTools(
            merge: { request, progress in
                await calls.add("merge \(request.inputs.count) -> \(request.output.lastPathComponent)")
                progress(1, 3)
                try await merge()
                return MapMergeReport(blocks: 5, written: 3, replaced: 0, overlaps: [], hasLevels: false, warnings: [], nextSteps: ["Run fill-sea on the merged map."])
            },
            fillSea: { _ in
                await calls.add("sea")
                return try await sea()
            },
            buildLevels: { request, progress in
                await calls.add("levels \(request.directory.lastPathComponent)")
                progress(LevelProgress(total: 6, finished: 2, running: 1, elapsed: .seconds(1)))
                try await levels()
                return LevelRunReport(
                    outcomes: [], summaries: [], manifestURL: request.directory.appendingPathComponent("manifest.json"), totalTime: .seconds(1),
                    peakFootprint: nil, openAreaChains: 0, areaEndsJoined: 0, areaEndsJoinedAlongBorder: 0, areaChainsClosedBySmallGap: 0)
            })
    }

    private func model(_ calls: Calls, tools: MapMergeTools, registered: Registered = Registered()) -> (MapMergeModel, Registered) {
        let root = URL(fileURLWithPath: "/tmp/geomapkit-merge-model")
        let inputs = [MapMergeModel.Input(name: "Switzerland", folder: root.appendingPathComponent("ch")), .init(name: "Spain", folder: root.appendingPathComponent("es"))]
        let model = MapMergeModel(inputs: inputs, output: .init(folder: root.appendingPathComponent("north"), name: "Northern Europe"), tools: tools, jobs: 2) { folder, name in
            registered.entries.append((folder, name))
            return "map-1"
        }
        return (model, registered)
    }

    @MainActor final class Registered {
        var entries: [(folder: URL, name: String)] = []
    }

    @Test("A run goes through the merge, the sea, the levels and the library, and the map has the name that was given")
    func fullRun() async {
        let calls = Calls()
        let (model, registered) = model(calls, tools: tools(calls))
        model.start()
        #expect(model.isRunning)
        await model.waitForRun()
        #expect(model.stage == .done(mapID: "map-1", name: "Northern Europe"))
        #expect(await calls.list == ["merge 2 -> north", "sea", "levels north"])
        #expect(registered.entries.map(\.name) == ["Northern Europe"] && model.report?.blocks == 5)
        #expect(model.levels?.finished == 2 && model.notes.isEmpty, "the note to run fill-sea and build-levels is not repeated: the app did both")
    }

    @Test("A sea that cannot be filled (no network) is a note, and the run goes on")
    func seaFails() async {
        let calls = Calls()
        let (model, _) = model(calls, tools: tools(calls, sea: { throw Failed() }))
        model.start()
        await model.waitForRun()
        #expect(model.stage == .done(mapID: "map-1", name: "Northern Europe"))
        #expect(model.notes.contains { $0.contains("sea between the maps was not filled") })
    }

    @Test("A merge that fails ends the run, and the sea and the levels are not tried")
    func mergeFails() async {
        let calls = Calls()
        let (model, registered) = model(calls, tools: tools(calls, merge: { throw MapBuilderError("the rule table is 20, not 21") }))
        model.start()
        await model.waitForRun()
        guard case .failed(let message) = model.stage else { Issue.record("not failed: \(model.stage)"); return }
        #expect(message.contains("rule table") && registered.entries.isEmpty)
        #expect(await calls.list == ["merge 2 -> north"])
    }

    @Test("A cancel in the levels stops the run, and Continue goes on without copying again or filling the sea again")
    func cancelAndContinue() async {
        let calls = Calls()
        let gate = Gate()
        let (model, registered) = model(calls, tools: tools(calls, levels: { try await gate.wait() }))
        model.start()
        for _ in 0..<500 where model.stage != .buildingLevels { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(model.stage == .buildingLevels)
        model.cancel()
        await model.waitForRun()
        #expect(model.stage == .cancelled && registered.entries.isEmpty)
        await gate.open()
        model.start()
        await model.waitForRun()
        #expect(model.stage == .done(mapID: "map-1", name: "Northern Europe"))
        #expect(await calls.list == ["merge 2 -> north", "sea", "levels north", "levels north"])
    }

    @Test("A name for a new map is a folder in the root that is not taken")
    func newFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-merge-root-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("North"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(MapMergeModel.newFolder(named: "North", in: root).lastPathComponent == "North 2")
        #expect(MapMergeModel.newFolder(named: "A/B: C", in: root).lastPathComponent == "A-B- C")
        #expect(MapMergeModel.newFolder(named: "  ", in: root).lastPathComponent == "Merged map")
    }

    /// Holds a step until the test lets it go; a cancel ends the wait.
    actor Gate {
        private var isOpen = false
        func open() { isOpen = true }
        func wait() async throws {
            while !isOpen { try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(5)) }
        }
    }

    // MARK: Plan

    private let root = URL(fileURLWithPath: "/tmp/geomapkit-plan-root")
    private func folders(_ id: String) -> URL? { id == "bad" ? nil : URL(fileURLWithPath: "/maps/\(id)") }

    @Test("A plan for a new map takes the folders of the maps and a folder in the root; the name is checked before anything runs")
    func planNew() throws {
        let plan = try MapMergeModel.plan(maps: [("a", "Alps"), ("b", "Benelux")], addTo: nil, name: " North ", root: root, folder: folders)
        #expect(plan.inputs.map(\.name) == ["Alps", "Benelux"] && plan.output.name == "North" && plan.output.folder.deletingLastPathComponent().path == root.path)
        #expect(throws: MapMergeModel.PlanError.self) { try MapMergeModel.plan(maps: [("a", "A"), ("b", "B")], addTo: nil, name: "a/b", root: root, folder: folders) }
        #expect(throws: MapMergeModel.PlanError.self) { try MapMergeModel.plan(maps: [("a", "A"), ("b", "B")], addTo: nil, name: "  ", root: root, folder: folders) }
        #expect(throws: MapMergeModel.PlanError.self) { try MapMergeModel.plan(maps: [("a", "A"), ("b", "B")], addTo: nil, name: "North", root: nil, folder: folders) }
    }

    @Test("Adding to a map puts it first, keeps its name and folder, and needs no name")
    func planInto() throws {
        let plan = try MapMergeModel.plan(maps: [("a", "A"), ("b", "B"), ("c", "C")], addTo: "c", name: "", root: nil, folder: folders)
        #expect(plan.inputs.first?.name == "C" && plan.output == .init(folder: URL(fileURLWithPath: "/maps/c"), name: "C"))
        #expect(Set(plan.inputs.map(\.name)) == ["A", "B", "C"])
    }

    @Test("Fewer than two maps, or a link that cannot be resolved, make no plan")
    func planRefused() {
        #expect(throws: MapMergeModel.PlanError.self) { try MapMergeModel.plan(maps: [("a", "A")], addTo: nil, name: "N", root: root, folder: folders) }
        #expect(throws: MapMergeModel.PlanError.self) { try MapMergeModel.plan(maps: [("a", "A"), ("bad", "Bad")], addTo: nil, name: "N", root: root, folder: folders) }
    }

    @Test("The notes of the merge are still there after a cancel and Continue")
    func notesSurviveContinue() async {
        let calls = Calls()
        let gate = Gate()
        let seen = tools(calls, levels: { try await gate.wait() })
        let withNote = MapMergeTools(
            merge: { request, progress in
                let base = try await seen.merge(request, progress)
                return MapMergeReport(blocks: base.blocks, written: base.written, replaced: 0, overlaps: [], hasLevels: false, warnings: ["2 tiles were in more than one map."], nextSteps: [])
            }, fillSea: seen.fillSea, buildLevels: seen.buildLevels)
        let (model, _) = model(calls, tools: withNote)
        model.start()
        for _ in 0..<500 where model.stage != .buildingLevels { try? await Task.sleep(for: .milliseconds(10)) }
        model.cancel()
        await model.waitForRun()
        await gate.open()
        model.start()
        await model.waitForRun()
        #expect(model.notes == ["2 tiles were in more than one map."])
    }
}
#endif
