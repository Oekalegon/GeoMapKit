#if os(macOS)
import Foundation
import Testing

@testable import GeoMapKitDemo

@Suite("SourceFolder")
struct SourceFolderTests {
    private func defaults() -> UserDefaults {
        let name = "geomapkit-sourcefolder-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Without a choice there is no folder; a chosen folder is resolved again, and reset takes it away")
    func chooseAndReset() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-sf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SourceFolder(defaults: defaults())
        #expect(store.resolve() == nil && !store.isChosen)
        try store.choose(folder)
        #expect(store.isChosen)
        #expect(store.resolve()?.resolvingSymlinksInPath().path == folder.resolvingSymlinksInPath().path)
        store.reset()
        #expect(store.resolve() == nil && !store.isChosen)
    }

    @Test("A folder that was deleted resolves to nothing, so the app falls back to its own folder")
    func deletedFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-sf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = SourceFolder(defaults: defaults())
        try store.choose(folder)
        try FileManager.default.removeItem(at: folder)
        #expect(store.resolve() == nil)
    }
}
#endif
