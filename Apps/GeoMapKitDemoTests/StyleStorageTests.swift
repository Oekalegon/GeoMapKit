import Foundation
import MapStyle
import Testing

@testable import GeoMapKitDemo

/// The storage layer of the styles: coordinated file access, where the styles live, and the move into iCloud.
@MainActor
@Suite("Style storage")
struct StyleStorageTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-styles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func coordinatedWriteReadMoveAndDeleteRoundTrip() throws {
        let dir = try folder()
        let file = dir.appendingPathComponent("a.json")
        try CoordinatedFiles.write(Data("one".utf8), to: file)
        try CoordinatedFiles.write(Data("two".utf8), to: file)
        #expect(String(decoding: try CoordinatedFiles.read(file), as: UTF8.self) == "two", "a write replaces")
        let moved = dir.appendingPathComponent("b.json")
        try CoordinatedFiles.move(from: file, to: moved)
        #expect(!FileManager.default.fileExists(atPath: file.path) && FileManager.default.fileExists(atPath: moved.path))
        try CoordinatedFiles.delete(moved)
        #expect(!FileManager.default.fileExists(atPath: moved.path))
        #expect(throws: (any Error).self) { try CoordinatedFiles.read(moved) }
        #expect(throws: (any Error).self) { try CoordinatedFiles.delete(moved) }
    }

    @Test func theFolderIsTheICloudOneOnlyWhenWantedAndAvailable() {
        let root = URL(filePath: "/tmp/lib"), container = URL(filePath: "/tmp/container")
        let cloud = StyleFolder.resolve(root: root, useICloud: true, ubiquityContainer: container)
        #expect(cloud.place == .iCloud && cloud.url.path == "/tmp/container/Documents/Styles")
        let fallback = StyleFolder.resolve(root: root, useICloud: true, ubiquityContainer: nil)
        #expect(fallback.place == .local && fallback.url.path == "/tmp/lib/Styles", "no container (not signed in, or an unsigned build): the local folder")
        #expect(StyleFolder.resolve(root: root, useICloud: false, ubiquityContainer: container).place == .local)
    }

    @Test func migrationCopiesWhatIsMissingAndNeverOverwritesOrRemoves() throws {
        let local = try folder(), cloud = try folder()
        try Data("mine".utf8).write(to: local.appendingPathComponent("Only here.json"))
        try Data("local version".utf8).write(to: local.appendingPathComponent("Both.json"))
        try Data("cloud version".utf8).write(to: cloud.appendingPathComponent("Both.json"))
        try Data("x".utf8).write(to: local.appendingPathComponent("notes.txt"))
        let result = StyleMigration.copyMissing(from: local, to: cloud)
        #expect(result.copied == ["Only here.json"] && result.kept == ["Both.json"] && result.failed.isEmpty)
        #expect(String(decoding: try Data(contentsOf: cloud.appendingPathComponent("Both.json")), as: UTF8.self) == "cloud version")
        #expect(FileManager.default.fileExists(atPath: local.appendingPathComponent("Only here.json").path), "the local copy stays as a backup")
        #expect(!FileManager.default.fileExists(atPath: cloud.appendingPathComponent("notes.txt").path))
        // A second run changes nothing.
        #expect(StyleMigration.copyMissing(from: local, to: cloud).copied.isEmpty)
    }

    @Test func aStyleThatICloudHasOnlyAsAPlaceholderIsNotOverwritten() throws {
        let local = try folder(), cloud = try folder()
        try Data("local".utf8).write(to: local.appendingPathComponent("Shared.json"))
        try Data().write(to: cloud.appendingPathComponent(".Shared.json.icloud"))
        let result = StyleMigration.copyMissing(from: local, to: cloud)
        #expect(result.copied.isEmpty && result.kept == ["Shared.json"])
        #expect(!FileManager.default.fileExists(atPath: cloud.appendingPathComponent("Shared.json").path))
    }

    @Test func aLibraryKeepsItsStylesInTheFolderItIsGiven() throws {
        let root = try folder(), shared = try folder().appendingPathComponent("Documents/Styles")
        let library = MapLibrary(root: root, stylesDirectory: shared, defaults: UserDefaults(suiteName: "geomapkit-\(UUID().uuidString)")!)
        let item = try library.addStyle(.standard, named: "Mine")
        #expect(library.url(of: item).deletingLastPathComponent().standardizedFileURL == shared.standardizedFileURL)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Styles/Mine.json").path))
        try library.rename(item, to: "Yours")
        #expect(library.styles.map(\.name) == ["Yours"])
        try library.delete(try #require(library.styles.first))
        #expect(library.styles.isEmpty)
    }
}
