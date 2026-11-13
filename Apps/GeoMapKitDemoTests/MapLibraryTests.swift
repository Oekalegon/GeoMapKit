import FeatureStore
import Foundation
import GeoCore
import MapStyle
import Testing

@testable import GeoMapKitDemo

/// The library of maps and styles: what is added, renamed, removed and chosen.
@MainActor
@Suite("Map library")
struct MapLibraryTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-demo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func library(_ root: URL) -> MapLibrary {
        MapLibrary(root: root.appendingPathComponent("library"), defaults: UserDefaults(suiteName: "geomapkit-demo-\(UUID().uuidString)")!)
    }

    /// A store file with one road in one cell.
    private func storeFile(named name: String, in folder: URL) throws -> URL {
        var writer = FeatureStoreWriter(
            boundingBox: BoundingBox(south: 59.0, west: 11.0, north: 59.3, east: 11.6), attribution: "© OpenStreetMap contributors, ODbL")
        let cell = try #require(TileID.containing(Coordinate(latitude: 59.1, longitude: 11.3), zoom: 13))
        let lon = Int32((cell.northWest.longitude * 1e7).rounded()), lat = Int32((cell.northWest.latitude * 1e7).rounded())
        try writer.add(
            StoredFeature(
                classID: FeatureClass.roadMajor.rawValue, kind: .line, objectType: .way, objectID: 1,
                parts: [GeometryPart(points: [PackedPoint(longitude: lon + 1_000, latitude: lat - 1_000), PackedPoint(longitude: lon + 9_000, latitude: lat - 1_000)])]),
            band: .detail, cell: cell)
        let url = folder.appendingPathComponent(name)
        try writer.data().write(to: url)
        return url
    }

    @Test func aStoreFileIsCopiedIntoTheLibraryAndListed() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = library(root)
        let source = try storeFile(named: "Halden.gmk", in: root)
        #expect(library.add([source]).errors.isEmpty)
        #expect(library.maps.map(\.name) == ["Halden"] && library.maps[0].kind == .file && (library.maps[0].bytes ?? 0) > 0)
        #expect(FileManager.default.fileExists(atPath: library.url(of: library.maps[0]).path), "a copy in the app's folder")
        // The same name again gets a number, and what was added is named, so that the app can open it.
        let again = library.add([source])
        #expect(again.errors.isEmpty && again.maps == ["Halden 2.gmk"])
        #expect(library.maps.map(\.name) == ["Halden", "Halden 2"])
    }

    @Test func somethingThatIsNotAMapOrAStyleIsRefusedWithAReason() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = library(root)
        let junk = root.appendingPathComponent("broken.gmk")
        try Data("not a store".utf8).write(to: junk)
        let text = root.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: text)
        let badStyle = root.appendingPathComponent("bad.json")
        try Data("{\"hello\": 1}".utf8).write(to: badStyle)
        let errors = library.add([junk, text, badStyle]).errors
        #expect(errors.count == 3 && library.maps.isEmpty && library.styles.isEmpty)
        #expect(errors.allSatisfy { ($0.errorDescription ?? "").isEmpty == false })
    }

    @Test func aStyleIsReadBeforeItIsAddedAndCanBeChosenPerMap() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = library(root)
        let styleFile = root.appendingPathComponent("Night.json")
        try MapStyle.watch.jsonData().write(to: styleFile)
        let store = try storeFile(named: "A.gmk", in: root)
        let added = library.add([styleFile, store])
        #expect(added.errors.isEmpty && added.maps == ["A.gmk"] && added.styles == ["Night.json"])
        let map = try #require(library.maps.first), style = try #require(library.styles.first)
        #expect(library.styleChoice(forMap: map.id) == .standard, "no choice yet")
        library.setStyleChoice(.user(style.id), forMap: map.id)
        #expect(library.styleChoice(forMap: map.id) == .user("Night.json"))
        #expect(try library.style(for: .user(style.id)).name == MapStyle.watch.name)
        // Renaming the style keeps it chosen; removing it falls back to the standard style.
        try library.rename(style, to: "Dusk")
        #expect(library.styleChoice(forMap: map.id) == .user("Dusk.json"))
        try library.delete(try #require(library.styles.first))
        #expect(library.styleChoice(forMap: map.id) == .standard)
    }

    @Test func aMapCanBeRenamedAndRemovedAndTheSelectionFollows() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = library(root)
        library.add([try storeFile(named: "One.gmk", in: root), try storeFile(named: "Two.gmk", in: root)])
        #expect(library.selectedMapID == "One.gmk", "the first map is selected when none was")
        let one = try #require(library.maps.first { $0.name == "One" }), two = try #require(library.maps.first { $0.name == "Two" })
        library.selectedMapID = one.id
        try library.rename(one, to: "First")
        #expect(library.maps.map(\.name) == ["First", "Two"] && library.selectedMapID == "First.gmk")
        #expect(throws: LibraryError.exists("Two")) { try library.rename(try #require(library.maps.first), to: "Two") }
        #expect(throws: LibraryError.self) { try library.rename(two, to: "a/b") }
        #expect(throws: LibraryError.self) { try library.rename(two, to: "  ") }
        try library.delete(try #require(library.maps.first { $0.name == "First" }))
        #expect(library.maps.map(\.name) == ["Two"] && library.selectedMapID == "Two.gmk", "the selection of a removed map moves to the first map that is left")
    }

    @Test func aMapOpensWhereItsAreaIs() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = library(root)
        library.add([try storeFile(named: "Halden.gmk", in: root)])
        let opened = try library.open(try #require(library.maps.first))
        #expect(abs(opened.center.latitude - 59.15) < 0.01 && abs(opened.center.longitude - 11.3) < 0.01)
        #expect((4...16).contains(opened.zoom) && opened.source.storageZoom == 13)
    }

    @Test func aFolderOfBlocksIsLinkedNotCopied() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        // A set of one block: the block file and a manifest.
        let blocks = root.appendingPathComponent("Set")
        try FileManager.default.createDirectory(at: blocks.appendingPathComponent("blocks"), withIntermediateDirectories: true)
        let block = try storeFile(named: "8-136-75.gmk", in: blocks.appendingPathComponent("blocks"))
        let data = try Data(contentsOf: block)
        let manifest = StoreManifest(
            formatVersion: try FeatureStoreFile(data: data).formatVersion, classifierVersion: 0, storageZoom: 13, blockZoom: 8, bands: [.detail],
            profile: "full", attribution: "© OpenStreetMap contributors, ODbL",
            blocks: [StoreManifest.Block(x: 136, y: 75, file: "blocks/8-136-75.gmk", bytes: Int64(data.count), builtAt: Date())])
        try manifest.jsonData().write(to: blocks.appendingPathComponent("manifest.json"))
        let library = library(root)
        #expect(library.add([blocks]).errors.isEmpty)
        let map = try #require(library.maps.first)
        #expect(map.kind == .blocks && map.name == "Set" && map.bytes == nil)
        #expect(!FileManager.default.fileExists(atPath: library.mapsDirectory.appendingPathComponent("blocks").path), "nothing was copied")
        let opened = try library.open(map)
        #expect(opened.source is StoreSet)
        // A folder without a manifest, and the manifest alone, are refused.
        let empty = root.appendingPathComponent("Empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(library.add([empty, blocks.appendingPathComponent("manifest.json")]).errors.count == 2)
    }

    @Test func theSelectionIsRememberedAndAFileThatIsGoneFallsAway() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = UserDefaults(suiteName: "geomapkit-demo-\(UUID().uuidString)")!
        let first = MapLibrary(root: root.appendingPathComponent("library"), defaults: defaults)
        first.add([try storeFile(named: "Keep.gmk", in: root)])
        first.selectedMapID = "Keep.gmk"
        let second = MapLibrary(root: root.appendingPathComponent("library"), defaults: defaults)
        #expect(second.selectedMapID == "Keep.gmk")
        try FileManager.default.removeItem(at: second.mapsDirectory.appendingPathComponent("Keep.gmk"))
        second.reload()
        #expect(second.selectedMapID == nil && second.maps.isEmpty, "nothing to select")
    }

    @Test func aStoreFileOverTheCopyLimitIsLinkedAndStillOpens() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = library(root)
        library.copyLimit = 10   // every file is "big"
        let source = try storeFile(named: "Big.gmk", in: root)
        let added = library.add([source])
        #expect(added.errors.isEmpty && added.maps == ["Big.maplink"])
        let map = try #require(library.maps.first)
        #expect(map.kind == .linkedFile && map.name == "Big")
        #expect(!FileManager.default.fileExists(atPath: library.mapsDirectory.appendingPathComponent("Big.gmk").path), "not copied")
        let opened = try library.open(map)
        #expect(opened.source.storageZoom == 13 && abs(opened.center.latitude - 59.15) < 0.01)
        // The file goes away: the link cannot be opened any more, with a reason.
        try FileManager.default.removeItem(at: source)
        #expect(throws: (any Error).self) { try library.open(map) }
    }

    /// A set of one block in a folder: the block file and a manifest.
    private func blockSet(named name: String, in root: URL) throws -> URL {
        let blocks = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: blocks.appendingPathComponent("blocks"), withIntermediateDirectories: true)
        let block = try storeFile(named: "8-136-75.gmk", in: blocks.appendingPathComponent("blocks"))
        let data = try Data(contentsOf: block)
        let manifest = StoreManifest(
            formatVersion: try FeatureStoreFile(data: data).formatVersion, classifierVersion: 0, storageZoom: 13, blockZoom: 8, bands: [.detail],
            profile: "full", attribution: "© OpenStreetMap contributors, ODbL",
            blocks: [StoreManifest.Block(x: 136, y: 75, file: "blocks/8-136-75.gmk", bytes: Int64(data.count), builtAt: Date())])
        try manifest.jsonData().write(to: blocks.appendingPathComponent("manifest.json"))
        return blocks
    }

    @Test func aMapTheAppBuiltIsAddedUnderItsNameAndOpens() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let blocks = try blockSet(named: "built", in: root)
        let library = library(root)
        let id = try library.addBuilt(folder: blocks, name: "Netherlands and Belgium")
        let map = try #require(library.maps.first)
        #expect(map.id == id && map.name == "Netherlands and Belgium" && map.kind == .blocks)
        #expect(try library.open(map).source is StoreSet)
    }

    @Test func buildingTheSameFolderAgainDoesNotAddASecondMap() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let blocks = try blockSet(named: "built", in: root)
        let library = library(root)
        let first = try library.addBuilt(folder: blocks, name: "Liechtenstein")
        let again = try library.addBuilt(folder: blocks, name: "Liechtenstein")
        #expect(first == again && library.maps.count == 1)
        // Another folder with the same name gets a name of its own.
        let other = try blockSet(named: "other", in: root)
        try library.addBuilt(folder: other, name: "Liechtenstein")
        #expect(library.maps.count == 2 && Set(library.maps.map(\.id)).count == 2)
    }

    @Test func aBuiltFolderWithoutAManifestOrWithABadNameIsRefused() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = library(root)
        let empty = root.appendingPathComponent("Empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(throws: LibraryError.self) { try library.addBuilt(folder: empty, name: "Nothing") }
        let blocks = try blockSet(named: "built", in: root)
        #expect(throws: LibraryError.self) { try library.addBuilt(folder: blocks, name: "a/b") }
        #expect(throws: LibraryError.self) { try library.addBuilt(folder: blocks, name: "  ") }
        #expect(library.maps.isEmpty)
    }
}
