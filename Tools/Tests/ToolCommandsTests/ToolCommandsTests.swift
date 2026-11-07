import Foundation
import Testing
import GeoCore
import OSMPBF
import ToolSupport
@testable import ToolCommands

@Suite("ToolRunner")
struct ToolRunnerTests {
    private func writeFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-\(UUID().uuidString).osm.pbf")
        try TinyPBF.make().write(to: url)
        return url
    }

    @Test("scan counts every object and reports the file")
    func scan() throws {
        let url = try writeFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let report = try ToolRunner.scan(url: url)
        #expect(report.nodes == 5)
        #expect(report.ways == 2)
        #expect(report.relations == 0)
        #expect(report.blocks == 2)
        #expect(report.fileSize > 0)
        #expect(report.fileName == url.lastPathComponent)
        #expect(report.header.requiredFeatures == ["OsmSchema-V0.6", "DenseNodes"])
    }

    @Test("cut reports the passes in order and a summary of the extract")
    func cut() throws {
        let url = try writeFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let box = BoundingBox(south: 47, west: 9, north: 48, east: 10)
        let report = try ToolRunner.cut(url: url, area: box)
        #expect(report.passes.map(\.pass) == [.insideNodes, .ways, .relations, .outsideNodes, .assembly])
        #expect(report.passes.allSatisfy { $0.duration >= .zero })
        #expect(report.summary.ways == 1)                  // way 10 crosses the box, way 11 does not
        #expect(report.summary.nodes == 3)                 // nodes 1 and 2 inside, node 3 outside
        #expect(report.summary.nodesOutsideBox == 1)
        #expect(report.summary.wayVertices == 3)
        #expect(report.summary.relations == 0)
        #expect(report.summary.missingNodes == 0)
        #expect(report.area == box)
    }

    @Test("a missing file is a ToolError")
    func missingFile() {
        let url = URL(fileURLWithPath: "/nonexistent/geomapkit-missing.osm.pbf")
        #expect(throws: ToolError.self) { try ToolRunner.scan(url: url) }
        #expect(throws: ToolError.self) {
            try ToolRunner.cut(url: url, area: BoundingBox(south: 0, west: 0, north: 1, east: 1))
        }
    }

    @Test("a file that is not a PBF file fails with a PBFError")
    func notAPBF() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-\(UUID().uuidString).osm.pbf")
        try Data("this is not a pbf file".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: PBFError.self) { try ToolRunner.scan(url: url) }
    }
}

@Suite("ReportFormatter")
struct ReportFormatterTests {
    @Test("a cut report prints a table and the extract counts")
    func cutText() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-\(UUID().uuidString).osm.pbf")
        try TinyPBF.make().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let report = try ToolRunner.cut(url: url, area: BoundingBox(south: 47, west: 9, north: 48, east: 10))
        let text = ReportFormatter.text(for: report)
        #expect(text.contains("1 nodes inside box"))
        #expect(text.contains("5 nodes outside box"))
        #expect(text.contains("assembly (in memory)"))
        #expect(text.contains("ways:      1"))
        #expect(text.contains("peak memory so far"))
        #expect(text.contains("Peak memory: footprint"))
    }

    @Test("a fixed report prints exact numbers")
    func fixedText() {
        let report = CutReport(
            fileName: "test.osm.pbf", fileSize: 3_501_761, area: BoundingBox(south: 1, west: 2, north: 3, east: 4),
            passes: [PassTiming(pass: .insideNodes, duration: .milliseconds(500), peakMemoryAtStart: 7_700_000)],
            totalTime: .milliseconds(500),
            summary: ExtractSummary(
                nodes: 358_095, taggedNodes: 20_152, nodesOutsideBox: 5_150, ways: 42_120, wayVertices: 455_641,
                relations: 1_030, incompleteRelations: 184, missingNodes: 0, memoryBytes: 20_500_000
            ),
            peakFootprint: nil, peakResident: 52_000_000
        )
        let text = ReportFormatter.text(for: report)
        #expect(text.contains("File: test.osm.pbf, 3.5 MB"))
        #expect(text.contains("0.50 s"))
        #expect(text.contains("7 MB/s"))                   // 3.5 MB in 0.5 s
        #expect(text.contains("358,095 (20,152 tagged, 5,150 outside the box)"))
        #expect(text.contains("1,030 (184 incomplete)"))
        #expect(text.contains("footprint n/a"))
        #expect(text.contains("extract in memory: 20.5 MB"))
    }
}
