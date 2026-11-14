import FeatureStoreBuilder
import Foundation
import GeoCore
import Testing

@testable import ToolCommands

@Suite("Border-scan command")
struct BorderScanCommandTests {
    private let area = BoundingBox(south: 47, west: 9, north: 48, east: 10)

    private func tinyFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-\(UUID().uuidString)-in.osm.pbf")
        try TinyPBF.make().write(to: url)
        return url
    }

    @Test("an area with no border relation is clean and counts nothing")
    func noBorders() throws {
        let input = try tinyFile()
        defer { try? FileManager.default.removeItem(at: input) }
        let report = try ToolRunner.borderScan(urls: [input], area: area)
        #expect(report.isClean && report.audit.memberWays == 0 && report.audit.stored == 0)
        let text = ReportFormatter.text(for: report)
        #expect(text.contains("Every border way in the area is stored or has a reason not to be."))
        #expect(!text.contains("NOT STORED"))
    }

    @Test("a missing file is an error")
    func missingFile() {
        #expect(throws: (any Error).self) {
            try ToolRunner.borderScan(urls: [URL(fileURLWithPath: "/nonexistent/none.osm.pbf")], area: area)
        }
    }

    @Test("the text lists the ways that are no border with no reason, with their tags and relations")
    func listsUnexpectedWays() throws {
        let input = try tinyFile()
        defer { try? FileManager.default.removeItem(at: input) }
        let cut = try ToolRunner.borderScan(urls: [input], area: area).cut
        var audit = BorderAuditReport()
        audit.memberWays = 12
        audit.stored = 8
        audit.expected = [.coastline: 1, .limitOfOneCountry: 2]
        audit.outsideStoredArea = 4
        audit.unexpected = [
            BorderAuditReport.Group(
                signature: "2 relations boundary=administrative admin_level=2 waterway=river", count: 1,
                examples: [BorderAuditReport.Example(wayID: 77, relations: ["Greece", "Turkey"])])
        ]
        let report = BorderScanReport(cut: cut, audit: audit, auditTime: .seconds(1))
        #expect(!report.isClean)
        let text = ReportFormatter.text(for: report)
        #expect(text.contains("stored as countryBorder:"))
        #expect(text.contains("a coastline (no border):"))
        #expect(text.contains("the limit of one country's waters (no border):"))
        #expect(text.contains("NOT STORED AS A BORDER, WITH NO REASON: 1 ways"))
        #expect(text.contains("2 relations boundary=administrative admin_level=2 waterway=river"))
        #expect(text.contains("way 77 in Greece | Turkey"))
        #expect(!text.contains("Every border way"))
    }
}
