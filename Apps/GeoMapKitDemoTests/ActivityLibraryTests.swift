import Foundation
import Testing

@testable import GeoMapKitDemo

/// The state the activities screen shows. The importing itself is the package's (`ActivityBatchImporter`) and is tested there.
@MainActor
@Suite("Activity library")
struct ActivityLibraryTests {
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-activities-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("A new library has an empty store file next to the tracks, nothing running and no problem")
    func empty() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = ActivityLibrary(root: root)
        await library.refresh()
        #expect(library.totals == ActivityLibrary.Totals() && !library.isRunning && library.problem == nil)
        #expect(FileManager.default.fileExists(atPath: library.url.path))
    }

    @Test("A store file of a newer version is reported, not replaced")
    func newer() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Activities.sqlite")
        try Data("not a database".utf8).write(to: file)
        let library = ActivityLibrary(root: root)
        #expect(library.problem != nil)
        #expect(try Data(contentsOf: file) == Data("not a database".utf8))
    }

    @Test("Cancelling with nothing running does nothing")
    func cancelIdle() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = ActivityLibrary(root: root)
        library.cancel()
        #expect(!library.isRunning)
    }
}
