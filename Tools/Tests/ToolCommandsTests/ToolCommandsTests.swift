import Foundation
import Testing
import FeatureStore
import FeatureStoreBuilder
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

@Suite("Build command")
struct BuildCommandTests {
    private func temporary(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-\(UUID().uuidString)-\(name)")
    }

    private func writeInput() throws -> URL {
        let url = temporary("in.osm.pbf")
        try TinyPBF.make().write(to: url)
        return url
    }

    // A one degree box holds many zoom 13 cells; only the ones the tiny file touches have features.
    private let box = BoundingBox(south: 47, west: 9, north: 48, east: 10)

    @Test("builds, writes and verifies a file")
    func builds() throws {
        let input = try writeInput(), output = temporary("out.gmk")
        defer { try? FileManager.default.removeItem(at: input); try? FileManager.default.removeItem(at: output) }
        let report = try ToolRunner.build(url: input, area: box, output: output, profile: .full)
        let file = try FeatureStoreFile(contentsOf: output)
        try file.verify()
        #expect(report.statistics == (try file.statistics()))
        #expect(report.statistics.fileBytes == (try Data(contentsOf: output)).count)
        #expect(report.outputName == output.lastPathComponent)
        #expect(report.cut.summary.ways == 1)
        #expect(report.statistics.cellCount > 0)
        #expect(report.buildTime >= .zero)
        #expect(report.profile == .full)
    }

    @Test("the watch profile builds too")
    func watch() throws {
        let input = try writeInput(), output = temporary("watch.gmk")
        defer { try? FileManager.default.removeItem(at: input); try? FileManager.default.removeItem(at: output) }
        let report = try ToolRunner.build(url: input, area: box, output: output, profile: .watch)
        #expect(report.profile == .watch)
        #expect(ReportFormatter.text(for: report).contains("Build (watch profile)"))
    }

    @Test("an output directory that does not exist fails before the cut")
    func missingDirectory() throws {
        let input = try writeInput()
        defer { try? FileManager.default.removeItem(at: input) }
        let output = URL(fileURLWithPath: "/nonexistent-geomapkit-dir/out.gmk")
        #expect(throws: ToolError.self) { try ToolRunner.build(url: input, area: box, output: output, profile: .full) }
    }

    @Test("an output path that is a directory is rejected")
    func outputIsDirectory() throws {
        let input = try writeInput()
        defer { try? FileManager.default.removeItem(at: input) }
        #expect(throws: ToolError.self) {
            try ToolRunner.build(url: input, area: box, output: FileManager.default.temporaryDirectory, profile: .full)
        }
    }

    @Test("a missing input file is a ToolError and nothing is written")
    func missingInput() {
        let output = temporary("never.gmk")
        #expect(throws: ToolError.self) {
            try ToolRunner.build(url: URL(fileURLWithPath: "/nonexistent/x.osm.pbf"), area: box, output: output, profile: .full)
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test("a fixed report prints exact numbers")
    func fixedText() {
        let cut = CutReport(
            fileName: "test.osm.pbf", fileSize: 3_501_761, area: BoundingBox(south: 1, west: 2, north: 3, east: 4),
            passes: [], totalTime: .milliseconds(250),
            summary: ExtractSummary(
                nodes: 1, taggedNodes: 0, nodesOutsideBox: 0, ways: 1, wayVertices: 1,
                relations: 0, incompleteRelations: 0, missingNodes: 0, memoryBytes: 1_000
            ),
            peakFootprint: nil, peakResident: 52_000_000
        )
        let statistics = FeatureStoreFile.Statistics(
            fileBytes: 3_900_000, cellCount: 22, stringCount: 1_234, stringTableBytes: 20_000, relationTableBytes: 5_000,
            cellBytes: 3_800_000, bandBytes: [.detail: 3_000_000, .mid: 600_000],
            featureCounts: [.detail: 120_000, .mid: 30_000], detailFeaturesByClass: [1: 4_500, 8: 900, 200: 3]
        )
        var counters = BuildReport()
        counters.nodesStored = 1_500
        counters.waysStored = 42_000
        counters.waysSuppressed = 300
        counters.relationsStored = 1_030
        counters.multipolygonsAssembled = 800
        counters.multipolygonsIncomplete = 12
        counters.piecesOutsideCells = 77
        counters.featuresSkippedByProfile = 9_001
        let text = ReportFormatter.text(for: BuildCommandReport(
            profile: .full, outputName: "out.gmk", cut: cut, buildTime: .milliseconds(450),
            statistics: statistics, report: counters))
        #expect(text.contains("File: test.osm.pbf, 3.5 MB"))
        #expect(text.contains("Build (full profile)"))
        #expect(text.contains("cut:   0.25 s"))
        #expect(text.contains("build: 0.45 s"))
        #expect(text.contains("out.gmk, 3.9 MB, 22 cells written (verified)"))
        #expect(text.contains("strings 20.0 kB (1,234 strings)"))
        #expect(text.contains("detail         3.0 MB    120,000"))
        #expect(text.contains("mid          600.0 kB     30,000"))
        #expect(text.contains("path" + String(repeating: " ", count: 17) + "4,500"))
        #expect(text.contains("forest" + String(repeating: " ", count: 17) + "900"))
        #expect(text.contains("unknown(200)"))
        #expect(text.contains("42,000 stored, 300 suppressed"))
        #expect(text.contains("800 assembled, 12 incomplete"))
        #expect(text.contains("pieces outside the cells: 77"))
        #expect(text.contains("features skipped by the profile: 9,001"))
    }
}

@Suite("Render command")
struct RenderCommandTests {
    private func temporary(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-\(UUID().uuidString)-\(name)")
    }

    @Test("renders a store to a PNG and reports what it drew")
    func renders() throws {
        let input = temporary("in.osm.pbf"), store = temporary("s.gmk"), png = temporary("m.png")
        defer { for url in [input, store, png] { try? FileManager.default.removeItem(at: url) } }
        try TinyPBF.make().write(to: input)
        _ = try ToolRunner.build(
            url: input, area: BoundingBox(south: 47, west: 9, north: 48, east: 10), output: store, profile: .full)
        let cell = try #require(try FeatureStoreFile(contentsOf: store).cells().first)
        let centre = Coordinate(
            latitude: (cell.northWest.latitude + cell.southEast.latitude) / 2,
            longitude: (cell.northWest.longitude + cell.southEast.longitude) / 2)

        let request = RenderRequest(center: centre, zoom: 15, width: 200, height: 150, scale: 2, style: .standard, output: png.path)
        let report = try ToolRunner.render(store: store, request: request)
        let data = try Data(contentsOf: png)
        #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
        #expect(report.pixelWidth == 400 && report.pixelHeight == 300)
        #expect(report.pngBytes == data.count)
        #expect(report.band == .detail)
        #expect(ReportFormatter.text(for: report).contains("400 x 300 px"))
    }

    @Test("a missing store is a ToolError and nothing is written")
    func missingStore() {
        let png = temporary("m.png")
        let request = RenderRequest(
            center: Coordinate(latitude: 47, longitude: 9), zoom: 15, width: 100, height: 100, scale: 1, style: .watch,
            output: png.path)
        #expect(throws: ToolError.self) { try ToolRunner.render(store: URL(fileURLWithPath: "/nonexistent/s.gmk"), request: request) }
        #expect(!FileManager.default.fileExists(atPath: png.path))
    }

    @Test("an output directory that does not exist is rejected")
    func missingDirectory() {
        let request = RenderRequest(
            center: Coordinate(latitude: 47, longitude: 9), zoom: 15, width: 100, height: 100, scale: 1, style: .standard,
            output: "/nonexistent/dir/m.png")
        #expect(throws: ToolError.self) { try ToolRunner.render(store: URL(fileURLWithPath: "/nonexistent/s.gmk"), request: request) }
    }
}
