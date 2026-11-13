import FeatureStoreBuilder
import Foundation
import Testing
@testable import FeatureStoreBuilder
@testable import MapBuilder
@testable import ToolCommands

/// How `build-region` and `build-levels` print what the pipeline reports.
@Suite("build report text")
struct BuildReportFormatTests {
    @Test("The progress lines and the summary of build-region read as text")
    func blockText() {
        let built = BlockOutcome(x: 134, y: 74, status: .built(bytes: 110_000_000, cells: 1_332, seconds: 84.2), regions: ["sweden", "ostlandet"])
        #expect(ReportFormatter.line(for: built, blockZoom: 8) == "block 8/134/74: built, 110.0 MB, 1,332 cells, 84.2 s (sweden, ostlandet)")
        #expect(ReportFormatter.line(for: BlockOutcome(x: 1, y: 2, status: .upToDate, regions: []), blockZoom: 8) == "block 8/1/2: up to date, left as it is")
        #expect(ReportFormatter.line(for: BlockOutcome(x: 1, y: 2, status: .empty, regions: ["x"]), blockZoom: 8).contains("nothing to store"))
        let report = BlockRunReport(
            outcomes: [built, BlockOutcome(x: 1, y: 2, status: .empty, regions: [])], manifestURL: URL(fileURLWithPath: "/out/manifest.json"),
            totalTime: .seconds(90), peakFootprint: 800_000_000, warnings: ["Sweden is old."],
            openSea: OpenSea.Report(created: [.init(x: 1, y: 2)], extended: [.init(x: 3, y: 4), .init(x: 5, y: 6)], conflicting: [.init(x: 7, y: 8)]))
        let text = ReportFormatter.text(for: report, blockZoom: 8)
        #expect(text.contains("Open sea: 1 blocks added, 2 completed with sea, 1 left because their neighbours disagree"))
        #expect(text.contains("2 in the area, 1 built (110.0 MB), 0 up to date, 1 with nothing to store"))
        #expect(text.contains("/out/manifest.json") && text.contains("warning: Sweden is old."))
    }

    @Test("The report and the lines of build-levels are readable")
    func levelText() {
        let outcome = LevelOutcome(topZoom: 8, x: 140, y: 75, status: .built(bytes: 4_000, features: 3, seconds: 0.1))
        let report = LevelRunReport(
            outcomes: [outcome], summaries: [LevelSummary(topZoom: 8, storageZoom: 10, blocks: 1, bytes: 4_000)],
            manifestURL: URL(fileURLWithPath: "/out/manifest.json"), totalTime: .seconds(1), peakFootprint: nil, openAreaChains: 0,
            areaEndsJoined: 0, areaEndsJoinedAlongBorder: 0, areaChainsClosedBySmallGap: 0)
        let text = ReportFormatter.text(for: report)
        #expect(text.contains("Level blocks: 1, 1 built") && text.contains("level 8 (cells of zoom 10): 1 block,"))
        #expect(text.contains("Area chains that did not close (drawn as outlines): 0"))
        #expect(ReportFormatter.line(for: outcome).hasPrefix("level 8 block 140/75: built"))
    }
}
