import Foundation
import GeoCore
import Testing

@testable import FeatureStore

/// The manifest of a set of block files and the reader that routes cells to the blocks.
@Suite("StoreSet")
struct StoreSetTests {
    /// Cells at storage zoom 13 on both sides of a block border of the zoom 8 grid (32 cells to a block).
    private let westCell = TileID(zoom: 13, x: 32 * 4 + 31, y: 32 * 3 + 5)!
    private let eastCell = TileID(zoom: 13, x: 32 * 5, y: 32 * 3 + 5)!
    private let farCell = TileID(zoom: 13, x: 32 * 9 + 2, y: 32 * 3 + 5)!

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-set-\(UUID().uuidString)")
    }

    /// Writes a block file with a named peak in each of the cells, in the mid and detail bands.
    @discardableResult
    private func writeBlock(
        _ name: String, cells: [TileID], in folder: URL, strings: [String] = [], classifier: UInt16 = 16, zoom: Int = 13
    ) throws -> Int64 {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var writer = FeatureStoreWriter(
            storageZoom: zoom, boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: "© OpenStreetMap contributors, ODbL",
            classifierVersion: classifier)
        // Strings of a block only differ in their numbers: the same name has another number in another block.
        // (Strings that no feature uses are not written, so each is the name of an extra point in the first cell.)
        for (number, text) in strings.enumerated() {
            guard let cell = cells.first else { break }
            try writer.add(
                StoredFeature(
                    classID: 5, kind: .point, objectType: .node, objectID: Int64(900_000 + number), nameID: writer.intern(text),
                    parts: [GeometryPart(points: [PackedPoint(longitude: Int32((cell.northWest.longitude * 1e7).rounded()) + 2_000, latitude: Int32((cell.northWest.latitude * 1e7).rounded()) - 2_000)])]),
                band: .detail, cell: cell)
        }
        for cell in cells {
            let name = writer.intern("Peak in \(cell.x)/\(cell.y)")
            let point = PackedPoint(longitude: Int32((cell.northWest.longitude * 1e7).rounded()) + 1_000, latitude: Int32((cell.northWest.latitude * 1e7).rounded()) - 1_000)
            for band in [ZoomBand.mid, .detail] {
                try writer.add(
                    StoredFeature(
                        classID: 5, kind: .point, objectType: .node, objectID: Int64(cell.x * 1_000 + cell.y), nameID: name,
                        parts: [GeometryPart(points: [point])]),
                    band: band, cell: cell)
            }
        }
        let url = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writer.data().write(to: url)
        return Int64(try writer.data().count)
    }

    private func manifest(_ blocks: [StoreManifest.Block], classifier: Int = 16, bands: [ZoomBand] = [.mid, .detail]) throws -> StoreManifest {
        let probe = try FeatureStoreFile(data: {
            var writer = FeatureStoreWriter(boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: "")
            try writer.add(
                StoredFeature(classID: 5, kind: .point, objectType: .node, objectID: 1, parts: [GeometryPart(points: [PackedPoint(longitude: 0, latitude: 0)])]),
                band: .detail, cell: TileID(zoom: 13, x: 1, y: 1)!)
            return try writer.data()
        }())
        return StoreManifest(
            formatVersion: probe.formatVersion, classifierVersion: classifier, storageZoom: 13, blockZoom: 8, bands: bands, profile: "full",
            attribution: "© OpenStreetMap contributors, ODbL", blocks: blocks)
    }

    /// The size of a file in the folder, as the manifest records it.
    private func bytes(of file: String, in folder: URL) -> Int64 {
        Int64((try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(file).path)[.size] as? Int) ?? 0)
    }

    private func block(_ x: Int, _ y: Int, file: String, bytes: Int64 = 100) -> StoreManifest.Block {
        StoreManifest.Block(
            x: x, y: y, file: file, bytes: bytes, builtAt: Date(timeIntervalSince1970: 1_800_000_000),
            sources: [StoreManifest.Source(regionID: "sweden", url: "https://download.example.org/sweden.osm.pbf", size: 5, downloadedAt: Date(timeIntervalSince1970: 1_790_000_000), etag: "\"e\"")])
    }

    /// A folder with the blocks 4/3 and 5/3 written, and the set over them.
    private func twoBlocks() throws -> (StoreSet, URL) {
        let folder = directory()
        let a = try writeBlock("blocks/8-4-3.gmk", cells: [westCell], in: folder)
        let b = try writeBlock("blocks/8-5-3.gmk", cells: [eastCell], in: folder, strings: ["0 filler one", "0 filler two", "0 filler three"])
        let set = try StoreSet(
            manifest: try manifest([block(4, 3, file: "blocks/8-4-3.gmk", bytes: a), block(5, 3, file: "blocks/8-5-3.gmk", bytes: b)]), directory: folder)
        return (set, folder)
    }

    // MARK: Manifest

    @Test("A manifest survives JSON and gives the same text twice")
    func roundTrip() throws {
        let original = try manifest([block(4, 3, file: "blocks/a.gmk"), block(5, 3, file: "blocks/b.gmk")])
        let data = try original.jsonData()
        #expect(try StoreManifest(json: data) == original)
        #expect(try original.jsonData() == data)
        #expect(String(decoding: data, as: UTF8.self).contains("\"blockZoom\""))
    }

    @Test("A manifest that does not hold together is refused with a reason")
    func validation() throws {
        func refused(_ change: (inout StoreManifest) -> Void) throws -> Bool {
            var broken = try manifest([block(4, 3, file: "blocks/a.gmk")])
            change(&broken)
            do { try broken.validate(); return false } catch is StoreSetError { return true }
        }
        #expect(try refused { $0.version = 2 })
        #expect(try refused { $0.blockZoom = 14 })
        #expect(try refused { $0.storageZoom = 31 })
        #expect(try refused { $0.bands = [] })
        #expect(try refused { $0.bands = [7] })
        #expect(try refused { $0.bands = [2, 1] }, "not ascending")
        #expect(try refused { $0.bands = [1, 1, 2] }, "a band twice")
        #expect(try refused { $0.profile = "huge" })
        #expect(try refused({ $0.blocks.append(StoreManifest.Block(x: 5, y: 3, file: "blocks/a.gmk", bytes: 1, builtAt: Date())) }), "one file for two blocks")
        #expect(try refused { $0.blocks.append($0.blocks[0]) }, "a block twice")
        #expect(try refused { $0.blocks[0].x = 256 }, "outside the grid")
        #expect(try refused { $0.blocks[0].y = -1 })
        #expect(try refused { $0.blocks[0].bytes = -5 })
        for path in ["/etc/passwd", "../a.gmk", "blocks/../../a.gmk", "", "a\\b.gmk", "blocks//a.gmk", "./a.gmk"] {
            #expect(try refused { $0.blocks[0].file = path }, "path \(path)")
        }
        #expect(throws: StoreSetError.unsupportedManifestVersion(9)) {
            var data = try manifest([]).jsonData()
            data = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 9").utf8)
            _ = try StoreManifest(json: data)
        }
        #expect(throws: StoreSetError.self) { try StoreManifest(json: Data("{}".utf8)) }
        #expect(throws: StoreSetError.self) { try StoreManifest(json: Data("not json".utf8)) }
    }

    @Test("A manifest file larger than the limit is refused without being read")
    func tooLarge() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("manifest.json")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(StoreManifest.maximumSize + 1))
        try handle.close()
        #expect(throws: StoreSetError.self) { try StoreSet(manifestURL: url) }
    }

    // MARK: Routing

    @Test("A cell is read from the block that holds it, with that block's own strings")
    func routing() throws {
        let (set, folder) = try twoBlocks()
        defer { try? FileManager.default.removeItem(at: folder) }
        let west = try #require(try set.file(containing: westCell))
        let east = try #require(try set.file(containing: eastCell))
        let westFeature = try #require(try west.features(in: westCell, band: .detail).first { $0.objectID == Int64(westCell.x * 1_000 + westCell.y) })
        let eastFeature = try #require(try east.features(in: eastCell, band: .detail).first { $0.objectID == Int64(eastCell.x * 1_000 + eastCell.y) })
        #expect(west.string(at: try #require(westFeature.nameID)) == "Peak in \(westCell.x)/\(westCell.y)")
        #expect(east.string(at: try #require(eastFeature.nameID)) == "Peak in \(eastCell.x)/\(eastCell.y)")
        // The number of a name means something else in another block, so the file that supplied the cell must read it.
        let number = try #require(eastFeature.nameID)
        #expect(west.string(at: number) != east.string(at: number))
        #expect(set.storageZoom == 13 && set.bands == [.mid, .detail] && set.attribution == "© OpenStreetMap contributors, ODbL")
    }

    @Test("A cell with no block, an empty cell of a block and a cell of another zoom give no file")
    func noFile() throws {
        let (set, folder) = try twoBlocks()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(try set.file(containing: farCell) == nil, "no block there")
        #expect(try set.file(containing: TileID(zoom: 13, x: 32 * 4 + 3, y: 32 * 3 + 5)!) == nil, "a block, but no such cell in it")
        #expect(try set.file(containing: TileID(zoom: 12, x: 4, y: 3)!) == nil, "another zoom")
        #expect(set.openBlockCount == 1, "only the block that was asked is open")
    }

    @Test("Blocks are opened when needed and at most the limit stay open")
    func limit() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        var blocks: [StoreManifest.Block] = []
        var cells: [TileID] = []
        for x in 0..<4 {
            let cell = TileID(zoom: 13, x: 32 * x + 1, y: 40)!
            cells.append(cell)
            let bytes = try writeBlock("b\(x).gmk", cells: [cell], in: folder)
            blocks.append(block(x, 1, file: "b\(x).gmk", bytes: bytes))
        }
        let set = try StoreSet(manifest: try manifest(blocks), directory: folder, maximumOpenBlocks: 2)
        #expect(set.openBlockCount == 0)
        for cell in cells { #expect(try set.file(containing: cell) != nil) }
        #expect(set.openBlockCount == 2)
        #expect(try set.file(containing: cells[0]) != nil, "a block that was closed opens again")
        #expect(set.openBlockCount == 2)
    }

    @Test("The area of the set is the union of its blocks, and a set without blocks has none")
    func area() throws {
        let (set, folder) = try twoBlocks()
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = try #require(TileID(zoom: 8, x: 4, y: 3)), b = try #require(TileID(zoom: 8, x: 5, y: 3))
        let box = try #require(set.boundingBox)
        #expect(box.west == a.northWest.longitude && box.east == b.southEast.longitude)
        #expect(box.north == a.northWest.latitude && box.south == a.southEast.latitude)
        #expect(try StoreSet(manifest: try manifest([]), directory: folder).boundingBox == nil)
    }

    // MARK: Blocks that do not fit

    @Test("A block that does not match the manifest, is damaged, or is missing is an error, not a wrong map")
    func mismatches() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cell = TileID(zoom: 13, x: 32 * 4 + 1, y: 32 * 3 + 5)!
        try writeBlock("old.gmk", cells: [cell], in: folder, classifier: 14)
        try writeBlock("zoom12.gmk", cells: [TileID(zoom: 12, x: 4 * 16 + 1, y: 3 * 16 + 2)!], in: folder, zoom: 12)
        try Data("not a store".utf8).write(to: folder.appendingPathComponent("garbage.gmk"))
        func open(_ file: String) throws -> FeatureStoreFile? {
            try StoreSet(manifest: try manifest([block(4, 3, file: file, bytes: bytes(of: file, in: folder))]), directory: folder).file(containing: cell)
        }
        #expect(throws: StoreSetError.self) { try open("old.gmk") }
        #expect(throws: StoreSetError.self) { try open("zoom12.gmk") }
        #expect(throws: StoreSetError.self) { try open("garbage.gmk") }
        #expect(throws: StoreSetError.blockMissing("gone.gmk")) { try open("gone.gmk") }
        // Bands that the manifest does not list.
        try writeBlock("fine.gmk", cells: [cell], in: folder)
        let fine = bytes(of: "fine.gmk", in: folder)
        let wrongBands = try StoreSet(manifest: try manifest([block(4, 3, file: "fine.gmk", bytes: fine)], bands: [.detail]), directory: folder)
        #expect(throws: StoreSetError.self) { try wrongBands.file(containing: cell) }
        // A sparse block holds fewer bands than the manifest lists (found on the real data: a block with only sea objects).
        let moreBands = try StoreSet(
            manifest: try manifest([block(4, 3, file: "fine.gmk", bytes: fine)], bands: [.overview, .mid, .detail]), directory: folder)
        #expect(try moreBands.file(containing: cell) != nil)
        #expect(try StoreSet(manifest: try manifest([block(4, 3, file: "fine.gmk", bytes: fine)]), directory: folder).file(containing: cell) != nil)
        // A file of another size than the manifest records: another build, or one that was not written to the end.
        let wrongSize = try StoreSet(manifest: try manifest([block(4, 3, file: "fine.gmk", bytes: fine + 1)]), directory: folder)
        do {
            _ = try wrongSize.file(containing: cell)
            Issue.record("a block of the wrong size was opened")
        } catch let error as StoreSetError {
            #expect("\(error)".contains("the manifest says \(fine + 1)"))
        }
    }

    @Test("A link inside the folder that leads out of it is not followed")
    func linkOutside() throws {
        let folder = directory(), outside = directory()
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: outside) }
        let cell = TileID(zoom: 13, x: 32 * 4 + 1, y: 32 * 3 + 5)!
        try writeBlock("real.gmk", cells: [cell], in: outside)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("linked.gmk"), withDestinationURL: outside.appendingPathComponent("real.gmk"))
        let set = try StoreSet(
            manifest: try manifest([block(4, 3, file: "linked.gmk", bytes: bytes(of: "real.gmk", in: outside))]), directory: folder)
        #expect(throws: StoreSetError.self) { try set.file(containing: cell) }
    }

    @Test("Many threads asking for cells of many blocks at once get the right files, and the limit holds")
    func threads() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        var blocks: [StoreManifest.Block] = []
        var cells: [TileID] = []
        for x in 0..<8 {
            let cell = TileID(zoom: 13, x: 32 * x + 1, y: 40)!
            cells.append(cell)
            let size = try writeBlock("t\(x).gmk", cells: [cell], in: folder)
            blocks.append(block(x, 1, file: "t\(x).gmk", bytes: size))
        }
        let set = try StoreSet(manifest: try manifest(blocks), directory: folder, maximumOpenBlocks: 2)
        let allCells = cells
        let wrong = await withTaskGroup(of: Int.self) { group in
            for round in 0..<200 {
                group.addTask {
                    let cell = allCells[round % allCells.count]
                    guard let file = try? set.file(containing: cell), let features = try? file.features(in: cell, band: .detail),
                        features.contains(where: { $0.objectID == Int64(cell.x * 1_000 + cell.y) })
                    else { return 1 }
                    return 0
                }
            }
            return await group.reduce(0, +)
        }
        #expect(wrong == 0)
        #expect(set.openBlockCount <= 2)
    }

    @Test("One file is a source too: it gives itself for the cells it has")
    func singleFile() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try writeBlock("one.gmk", cells: [westCell], in: folder)
        let file = try FeatureStoreFile(contentsOf: folder.appendingPathComponent("one.gmk"))
        #expect(try file.file(containing: westCell) != nil && file.file(containing: eastCell) == nil)
    }
}
