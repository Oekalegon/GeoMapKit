import Foundation
import GeoCore
import Testing
import ToolSupport

@testable import ToolCommands

@Suite("Inspect command")
struct InspectCommandTests {
    private func temporary(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-\(UUID().uuidString)-\(name)")
    }

    private func builtStore() throws -> URL {
        let input = temporary("in.osm.pbf"), store = temporary("s.gmk")
        defer { try? FileManager.default.removeItem(at: input) }
        try TinyPBF.make().write(to: input)
        _ = try ToolRunner.build(url: input, area: BoundingBox(south: 47, west: 9, north: 48, east: 10), output: store, profile: .full)
        return store
    }

    @Test("counts an object once however many cells it was cut into")
    func countsObjects() throws {
        let store = try builtStore()
        defer { try? FileManager.default.removeItem(at: store) }
        let report = try ToolRunner.inspect(store: store)
        // The tiny file has one way, which crosses several cells; it has no tags, so it is `other`.
        #expect(report.objectsByClass.first { $0.name == "other" }?.objects == 1)
        #expect(report.objectsByClass.reduce(0) { $0 + $1.objects } == 1)
        #expect(report.objectsByClass.count == 30, "every class is listed, also the empty ones")
        #expect(report.inspectedClass == nil && report.topTags.isEmpty)
    }

    @Test("a class can be inspected, and an unknown class name lists the known ones")
    func classNames() throws {
        let store = try builtStore()
        defer { try? FileManager.default.removeItem(at: store) }
        let report = try ToolRunner.inspect(store: store, className: "other")
        #expect(report.inspectedClass == "other")
        let text = ReportFormatter.text(for: report)
        #expect(text.contains("Objects in ") && text.contains("Most common tags in class other"))
        do {
            _ = try ToolRunner.inspect(store: store, className: "sidewalk")
            Issue.record("an unknown class should throw")
        } catch let error as ToolError {
            #expect("\(error)".contains("Unknown class 'sidewalk'") && "\(error)".contains("pavement"))
        }
    }

    @Test("a file that is not a store is a ToolError")
    func notAStore() {
        #expect(throws: ToolError.self) { try ToolRunner.inspect(store: URL(fileURLWithPath: "/nonexistent/x.gmk")) }
    }
}
