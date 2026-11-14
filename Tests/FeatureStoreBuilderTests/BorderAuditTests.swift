import Foundation
import Testing

@testable import FeatureStoreBuilder

/// The audit of the national borders: what the builder stores as `countryBorder` against the ways of the relations.
@Suite("Border audit")
struct BorderAuditTests {
    private let level2: [(String, String)] = [("boundary", "administrative"), ("admin_level", "2")]
    private let relationTags: [[(String, String)]] = [
        [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "2"), ("name", "Suomi")],
        [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "2"), ("name", "Россия")],
    ]

    /// A way (id 10) across the block, in the national border relations: both, or only the first.
    private func world(tags: [(String, String)], relations: Int = 2) -> SyntheticWorld {
        var world = SyntheticWorld()
        world.node(1, 0.5, 1.0); world.node(2, 1.5, 1.0); world.node(3, 2.5, 1.0)
        world.way(10, [1, 2, 3], tags)
        for index in 0..<relations { world.relation(Int64(50 + index), [(10, "outer", 1)], relationTags[index]) }
        return world
    }

    @Test("A border that the builder stores is counted as stored, and the report is clean")
    func storedBorder() throws {
        var shared = world(tags: level2)
        let report = try BorderAudit.run(on: try shared.extract())
        #expect(report.memberWays == 1 && report.stored == 1 && report.isClean)
        // The Evros: a river tagged as the limit of the waters that two countries share is a border (PR 111).
        var river = world(tags: level2 + [("border_type", "territorial"), ("waterway", "river")])
        let riverReport = try BorderAudit.run(on: try river.extract())
        #expect(riverReport.stored == 1 && riverReport.isClean)
    }

    @Test("The limit of the waters of one country, and a coastline, are no border and no failure")
    func expectedWays() throws {
        var limit = world(tags: level2 + [("border_type", "territorial")], relations: 1)
        let limitReport = try BorderAudit.run(on: try limit.extract())
        #expect(limitReport.stored == 0 && limitReport.expected == [.limitOfOneCountry: 1] && limitReport.isClean)
        var coast = world(tags: [("natural", "coastline")])
        let coastReport = try BorderAudit.run(on: try coast.extract())
        #expect(coastReport.expected == [.coastline: 1] && coastReport.isClean)
    }

    @Test("A way of a border relation that is not stored is reported with its tags and relations, grouped, with a few examples")
    func unexpectedWays() throws {
        var group = world(tags: level2 + [("waterway", "river")])
        group.node(4, 0.5, 1.5); group.node(5, 1.5, 1.5)
        for id in 11...14 {
            group.way(Int64(id), [4, 5], level2 + [("waterway", "river")])
            group.relation(Int64(60 + id), [(Int64(id), "outer", 1)], relationTags[0])
        }
        let extract = try group.extract()
        // Nothing stored: a border that was lost.
        let report = BorderAudit.audit(extract, stored: [], maxExamples: 2)
        #expect(!report.isClean && report.unexpectedCount == 5)
        let first = try #require(report.unexpected.first)
        #expect(first.signature == "1 relation boundary=administrative admin_level=2 waterway=river" && first.count == 4)
        #expect(first.examples.count == 2, "only as many examples as asked")
        let shared = try #require(report.unexpected.last)
        #expect(shared.signature == "2 relations boundary=administrative admin_level=2 waterway=river")
        #expect(shared.examples == [BorderAuditReport.Example(wayID: 10, relations: ["Suomi", "Россия"].sorted())])
        // Stored: the same extract is clean again.
        #expect(BorderAudit.audit(extract, stored: [10, 11, 12, 13, 14]).isClean)
    }

    @Test("A way the relation names but the file lacks, and a way outside the stored area, are counted and not listed")
    func outsideTheArea() throws {
        var outside = world(tags: level2)
        // A second member, far outside the block, and one that is not in the file.
        outside.node(7, 6.0, 6.0); outside.node(8, 6.5, 6.0)
        outside.way(20, [7, 8], level2)
        outside.relation(52, [(10, "outer", 1), (20, "outer", 1), (21, "outer", 1)], relationTags[0])
        let report = BorderAudit.audit(try outside.extract(), stored: [10])
        #expect(report.memberWays == 3 && report.stored == 1 && report.isClean)
        #expect(report.outsideStoredArea + report.notInExtract == 2 && report.notInExtract >= 1)
    }
}
