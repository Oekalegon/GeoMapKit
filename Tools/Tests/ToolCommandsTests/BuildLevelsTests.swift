import FeatureStore
import Foundation
import GeoCore
import MapStyle
import Testing
import ToolSupport

@testable import ToolCommands

/// `build-levels`: coarse levels added to a set of blocks.
@Suite("build-levels")
struct BuildLevelsTests {
    /// The cells of zoom 13 in block 8/140/75 (Stockholm), where a road runs across three of them.
    private let column = 32 * 140 + 8
    private let row = 32 * 75 + 8

    private func pt(_ lon: Int32, _ lat: Int32) -> PackedPoint { PackedPoint(longitude: lon, latitude: lat) }

    /// A folder with one block of a set: a major road over three cells, in all bands, and its `manifest.json`.
    private func blocks(profileBands: [ZoomBand] = [.overview, .mid, .detail], extraRoad: Bool = false) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-levels-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("blocks"), withIntermediateDirectories: true)
        var writer = FeatureStoreWriter(
            boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: "© OpenStreetMap contributors, ODbL",
            classifierVersion: 18)
        let cells = (0..<3).map { TileID(zoom: 13, x: column + $0, y: row)! }
        let rects = cells.map { (west: Int32(($0.northWest.longitude * 1e7).rounded()), east: Int32(($0.southEast.longitude * 1e7).rounded())) }
        let north = Int32((cells[0].northWest.latitude * 1e7).rounded()), south = Int32((cells[0].southEast.latitude * 1e7).rounded())
        let lat = north / 2 + south / 2
        for band in profileBands {
            for (index, cell) in cells.enumerated() {
                let start = rects[index].west + (index == 0 ? 5_000 : 0), end = rects[index].east - (index == 2 ? 5_000 : 0)
                var flags: FeatureFlags = []
                if index > 0 { flags.insert(.continuesBefore) }
                if index < 2 { flags.insert(.continuesAfter) }
                try writer.add(
                    StoredFeature(
                        classID: FeatureClass.roadMajor.rawValue, kind: .line, objectType: .way, objectID: 7, flags: flags,
                        parts: [GeometryPart(points: [pt(start, lat), pt(end, lat)])]),
                    band: band, cell: cell)
            }
        }
        if extraRoad {
            // A second road in the first cell: another build of the same block.
            try writer.add(
                StoredFeature(
                    classID: FeatureClass.roadMajor.rawValue, kind: .line, objectType: .way, objectID: 8,
                    parts: [GeometryPart(points: [pt(rects[0].west + 1_000, lat + 2_000), pt(rects[0].east - 1_000, lat + 2_000)])]),
                band: .overview, cell: cells[0])
        }
        let data = try writer.data()
        try data.write(to: folder.appendingPathComponent("blocks/8-140-75.gmk"))
        let manifest = StoreManifest(
            formatVersion: try FeatureStoreFile(data: data).formatVersion, classifierVersion: 18, storageZoom: 13, blockZoom: 8,
            bands: profileBands, profile: profileBands.contains(.overview) ? "full" : "watch", attribution: "© OpenStreetMap contributors, ODbL",
            blocks: [StoreManifest.Block(x: 140, y: 75, file: "blocks/8-140-75.gmk", bytes: Int64(data.count), builtAt: Date())])
        try manifest.jsonData().write(to: folder.appendingPathComponent("manifest.json"))
        return folder
    }

    private func read(_ folder: URL) throws -> StoreManifest {
        try StoreManifest(json: try Data(contentsOf: folder.appendingPathComponent("manifest.json")))
    }

    private func built(_ report: LevelRunReport) -> Int {
        report.outcomes.filter { if case .built = $0.status { return true } else { return false } }.count
    }

    @Test("Levels are built, listed in a version 2 manifest, and can be read")
    func buildsLevels() async throws {
        let folder = try blocks()
        defer { try? FileManager.default.removeItem(at: folder) }
        var seen: [LevelOutcome] = []
        let report = try await ToolRunner.buildLevels(LevelRequest(directory: folder, topZooms: [8, 6]), progress: { seen.append($0) })
        #expect(report.outcomes.count == 2 && built(report) == 2 && seen.count == 2)
        let manifest = try read(folder)
        #expect(manifest.version == 2 && manifest.levels.map(\.topZoom) == [8, 6])
        #expect(manifest.levels.map(\.storageZoom) == [10, 8] && manifest.levels.map(\.blockZoom) == [8, 8])
        #expect(manifest.levels[0].classes.contains(Int(FeatureClass.roadMajor.rawValue)))
        #expect(report.summaries.map(\.topZoom) == [8, 6] && report.summaries.allSatisfy { $0.blocks == 1 && $0.bytes > 0 })
        for level in manifest.levels {
            let block = try #require(level.blocks.first)
            #expect(block.derivedFrom == [.init(x: 140, y: 75, bytes: try #require(manifest.blocks.first).bytes)])
            let file = try FeatureStoreFile(contentsOf: folder.appendingPathComponent(block.file))
            try file.verify()
            let size = Int64(try Data(contentsOf: folder.appendingPathComponent(block.file)).count)
            #expect(file.storageZoom == level.storageZoom && file.bands == [.overview] && size == block.bytes)
        }
        // The set still opens, with its levels.
        #expect(try StoreSet(manifestURL: folder.appendingPathComponent("manifest.json")).manifest.levels.count == 2)
    }

    @Test("A second run leaves the levels, a changed block rebuilds the levels that read it, and a changed class set rebuilds a level")
    func resumesAndRebuilds() async throws {
        let folder = try blocks()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try await ToolRunner.buildLevels(LevelRequest(directory: folder, topZooms: [8, 6]))
        let again = try await ToolRunner.buildLevels(LevelRequest(directory: folder, topZooms: [8, 6]))
        #expect(built(again) == 0 && again.outcomes.allSatisfy { $0.status == .upToDate })

        // The base block is another build (another size, another content): its levels are out of date.
        let other = try blocks(extraRoad: true)
        defer { try? FileManager.default.removeItem(at: other) }
        let newFile = try Data(contentsOf: other.appendingPathComponent("blocks/8-140-75.gmk"))
        try newFile.write(to: folder.appendingPathComponent("blocks/8-140-75.gmk"))
        var manifest = try read(folder)
        manifest.blocks[0].bytes = Int64(newFile.count)
        try manifest.jsonData().write(to: folder.appendingPathComponent("manifest.json"))
        let rebuilt = try await ToolRunner.buildLevels(LevelRequest(directory: folder, topZooms: [8, 6]))
        #expect(built(rebuilt) == 2)

        // The Watch style shows no road at zoom 8: the class set of the level changes, the level has nothing, and its file goes.
        let oldFile = try #require(try read(folder).levels.first { $0.topZoom == 8 }?.blocks.first?.file)
        let watch = try await ToolRunner.buildLevels(LevelRequest(directory: folder, topZooms: [8], style: .watch))
        #expect(watch.outcomes.map(\.status) == [.empty])
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(oldFile).path))
        #expect(try read(folder).levels.map(\.topZoom) == [6], "the level that was not asked for stays")
    }

    @Test("Folders and arguments that do not fit are refused")
    func refuses() async throws {
        let folder = try blocks()
        defer { try? FileManager.default.removeItem(at: folder) }
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-none-\(UUID().uuidString)")
        await #expect(throws: ToolError.self) { try await ToolRunner.buildLevels(LevelRequest(directory: empty)) }
        await #expect(throws: ToolError.self) { try await ToolRunner.buildLevels(LevelRequest(directory: folder, topZooms: [])) }
        await #expect(throws: ToolError.self) { try await ToolRunner.buildLevels(LevelRequest(directory: folder, topZooms: [8, 8])) }
        await #expect(throws: ToolError.self) { try await ToolRunner.buildLevels(LevelRequest(directory: folder, topZooms: [11])) }
        await #expect(throws: ToolError.self) { try await ToolRunner.buildLevels(LevelRequest(directory: folder, margin: -1)) }
        // A Watch copy has no overview band to make levels from.
        let watch = try blocks(profileBands: [.mid, .detail])
        defer { try? FileManager.default.removeItem(at: watch) }
        await #expect(throws: ToolError.self) { try await ToolRunner.buildLevels(LevelRequest(directory: watch)) }
    }

    @Test("The report and the lines are readable")
    func formats() async throws {
        let folder = try blocks()
        defer { try? FileManager.default.removeItem(at: folder) }
        let report = try await ToolRunner.buildLevels(LevelRequest(directory: folder, topZooms: [8]))
        let text = ReportFormatter.text(for: report)
        #expect(text.contains("Level blocks: 1, 1 built") && text.contains("level 8 (cells of zoom 10): 1 blocks"))
        #expect(ReportFormatter.line(for: report.outcomes[0]).hasPrefix("level 8 block 140/75: built"))
    }
}
