import FeatureStore
import Foundation
import Regions
import Testing

@testable import GeoMapKitDemo

/// The list of downloaded files: which maps were built from each, and deleting them.
@MainActor
@Suite("Source files")
struct SourceFilesModelTests {
    struct Rig {
        let model: SourceFilesModel
        let cache: SourceCache
        let root: URL
        let maps: URL
    }

    private func rig(names: [String: String] = ["norway": "Norge", "sweden": "Sverige", "finland": "Suomi"]) throws -> Rig {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-files-\(UUID().uuidString)", isDirectory: true)
        let maps = root.appendingPathComponent("Maps", isDirectory: true)
        try FileManager.default.createDirectory(at: maps, withIntermediateDirectories: true)
        let cache = SourceCache(directory: root.appendingPathComponent("Sources"), availableCapacity: { _ in 5_000_000_000 })
        let model = SourceFilesModel(cache: cache, mapsRoot: maps) { names[$0] ?? $0 }
        return Rig(model: model, cache: cache, root: root, maps: maps)
    }

    private func store(_ cache: SourceCache, _ id: String, bytes: Int) throws {
        let part = try cache.preparePart(regionID: id, etag: "\"e\"", keepBytes: false)
        try Data(repeating: 7, count: bytes).write(to: part)
        try cache.install(regionID: id, from: URL(string: "https://download.example.org/\(id).osm.pbf")!, info: RemoteFileInfo(size: Int64(bytes), etag: "\"e\""))
    }

    /// A folder of blocks in `Maps` whose manifest says the blocks were built from these regions.
    private func map(_ name: String, in maps: URL, from regions: [[String]]) throws {
        let folder = maps.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let blocks = regions.enumerated().map { index, ids in
            StoreManifest.Block(
                x: index, y: 0, file: "blocks/8-\(index)-0.gmk", bytes: 10, builtAt: Date(),
                sources: ids.map { StoreManifest.Source(regionID: $0, url: "https://example.org/\($0)", size: 1, downloadedAt: Date()) })
        }
        let manifest = StoreManifest(
            formatVersion: 1, classifierVersion: 0, storageZoom: 13, blockZoom: 8, bands: [.detail], profile: "full",
            attribution: "© OpenStreetMap contributors, ODbL", blocks: blocks)
        try manifest.jsonData().write(to: folder.appendingPathComponent("manifest.json"))
    }

    @Test("The files are listed by name with the maps they were built from, and the files no map needs are the unused ones")
    func listsFilesAndTheirMaps() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        try store(r.cache, "norway", bytes: 1000)
        try store(r.cache, "sweden", bytes: 2000)
        try store(r.cache, "finland", bytes: 300)
        // Norway is in two maps (one of them a border block with Sweden); Sweden only as a neighbour in the first.
        try map("norway", in: r.maps, from: [["norway"], ["norway", "sweden"]])
        try map("norway-and-more", in: r.maps, from: [["norway"]])
        // A folder with no manifest, and one with a manifest that cannot be read, are no map.
        try FileManager.default.createDirectory(at: r.maps.appendingPathComponent("empty"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: r.maps.appendingPathComponent("broken"), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: r.maps.appendingPathComponent("broken/manifest.json"))

        await r.model.reload(mapNames: ["norway": "Norway", "norway-and-more": "Norway and more"])
        #expect(r.model.files.map(\.name) == ["Norge", "Sverige", "Suomi"].sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        let byID = Dictionary(uniqueKeysWithValues: r.model.files.map { ($0.regionID, $0) })
        #expect(byID["norway"]?.usedBy == ["Norway", "Norway and more"])
        #expect(byID["sweden"]?.usedBy == ["Norway"])
        #expect(byID["finland"]?.usedBy == [])
        #expect(r.model.totalBytes == 3300 && r.model.availableBytes == 5_000_000_000)
        #expect(r.model.unused.map(\.regionID) == ["finland"])
    }

    @Test("A folder that is not in the library is named after the folder")
    func unnamedFolder() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        try store(r.cache, "norway", bytes: 10)
        try map("europe-norway", in: r.maps, from: [["norway"]])
        await r.model.reload()
        #expect(r.model.files.first?.usedBy == ["europe-norway"])
    }

    @Test("A file is deleted with its record, and a map built from it is not touched")
    func deleteOne() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        try store(r.cache, "norway", bytes: 1000)
        try map("norway", in: r.maps, from: [["norway"]])
        await r.model.reload()
        try r.model.delete(try #require(r.model.files.first), isBusy: false)
        await r.model.reload()
        #expect(r.model.files.isEmpty && r.cache.entries().isEmpty)
        #expect(FileManager.default.fileExists(atPath: r.maps.appendingPathComponent("norway/manifest.json").path))
    }

    @Test("Nothing is deleted while a map is being built")
    func busy() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        try store(r.cache, "norway", bytes: 1000)
        await r.model.reload()
        let file = try #require(r.model.files.first)
        #expect(throws: SourceFilesModel.Failure.busy) { try r.model.delete(file, isBusy: true) }
        #expect(throws: SourceFilesModel.Failure.busy) { try r.model.deleteUnused(isBusy: true) }
        #expect(r.cache.entries().count == 1)
    }

    @Test("An unfinished download is deleted without the file of its region")
    func deleteUnfinished() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        try store(r.cache, "norway", bytes: 1000)
        try Data(repeating: 1, count: 40).write(to: try r.cache.preparePart(regionID: "norway", etag: "\"v2\"", keepBytes: false))
        await r.model.reload()
        let unfinished = try #require(r.model.files.first { $0.state == .unfinished })
        #expect(unfinished.bytes == 40)
        try r.model.delete(unfinished, isBusy: false)
        await r.model.reload()
        #expect(r.model.files.count == 1 && r.model.files.first?.bytes == 1000)
    }

    @Test("Delete unused removes the files no map needs, the damaged ones and the unfinished downloads, and keeps the rest")
    func deleteUnused() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        try store(r.cache, "norway", bytes: 1000)
        try store(r.cache, "sweden", bytes: 2000)
        try store(r.cache, "finland", bytes: 300)
        try Data(repeating: 1, count: 5).write(to: r.cache.fileURL(forRegionID: "finland"))   // damaged: the record says 300
        try Data(repeating: 1, count: 40).write(to: try r.cache.preparePart(regionID: "denmark", etag: nil, keepBytes: false))
        try map("norway", in: r.maps, from: [["norway"]])
        await r.model.reload()
        #expect(r.model.unused.count == 3, "sweden, the damaged finland and the unfinished denmark")
        let freed = try r.model.deleteUnused(isBusy: false)
        #expect(freed == 2000 + 5 + 40)
        await r.model.reload()
        #expect(r.model.files.map(\.regionID) == ["norway"])
    }
}
