import FeatureStore
import Foundation
import GeoCore
import Testing

@testable import FeatureStoreBuilder

/// Open sea far from a coast has no coastline in its cut and so no sea of its own; the pass gives it the sea its neighbours show.
@Suite("Open sea")
struct OpenSeaTests {
    private typealias Position = OpenSea.Position

    private let attribution = "© OpenStreetMap contributors, ODbL"
    private let bands: [ZoomBand] = [.overview, .mid, .detail]

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("opensea-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("blocks"), withIntermediateDirectories: true)
        return url
    }

    private func cells(of block: Position) -> [TileID] {
        (0..<32).flatMap { dy in (0..<32).map { dx in TileID(zoom: 13, x: block.x * 32 + dx, y: block.y * 32 + dy)! } }
    }

    private func seaSquare(_ cell: TileID) -> StoredFeature {
        StoredFeature(
            classID: FeatureClass.sea.rawValue, kind: .area, objectType: .way, objectID: 0,
            parts: [SeaBuilder.wholeCell(CellRect(tile: cell))])
    }

    private func coastline(_ cell: TileID) -> StoredFeature {
        let rect = CellRect(tile: cell)
        let lat = (rect.north + rect.south) / 2
        return StoredFeature(
            classID: FeatureClass.coastline.rawValue, kind: .line, objectType: .way, objectID: 7,
            parts: [GeometryPart(points: [PackedPoint(longitude: rect.west, latitude: lat), PackedPoint(longitude: rect.east, latitude: lat)])])
    }

    private enum Content {
        /// Sea squares everywhere and one coastline in the first cell.
        case sea
        /// A coastline in the first cell and nothing else (land).
        case land
        /// Only a country border line and a name, a relation, and no sea or coastline.
        case sparse
    }

    private func write(_ content: Content, at block: Position, in folder: URL) throws -> StoreManifest.Block {
        var writer = FeatureStoreWriter(
            boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: attribution, classifierVersion: 16)
        let all = cells(of: block)
        switch content {
        case .sea:
            for cell in all { for band in bands { try writer.add(seaSquare(cell), band: band, cell: cell) } }
            try writer.add(coastline(all[0]), band: .overview, cell: all[0])
        case .land:
            try writer.add(coastline(all[0]), band: .overview, cell: all[0])
        case .sparse:
            let rect = CellRect(tile: all[100])
            let lat = (rect.north + rect.south) / 2
            let name = writer.intern("Grensen"), key = writer.intern("boundary"), value = writer.intern("administrative")
            let role = writer.intern("outer")
            try writer.add(StoredRelation(id: 99, tags: [StoredTag(key: key, value: value)], members: [StoredRelationMember(type: .way, id: 5, role: role)]))
            let feature = StoredFeature(
                classID: FeatureClass.countryBorder.rawValue, kind: .line, objectType: .way, objectID: 5, nameID: name,
                tags: [StoredTag(key: key, value: value)],
                parts: [GeometryPart(points: [PackedPoint(longitude: rect.west, latitude: lat), PackedPoint(longitude: rect.east, latitude: lat)])])
            for band in bands { try writer.add(feature, band: band, cell: all[100]) }
        }
        let name = "blocks/8-\(block.x)-\(block.y).gmk"
        let data = try writer.data()
        try data.write(to: folder.appendingPathComponent(name))
        return StoreManifest.Block(x: block.x, y: block.y, file: name, bytes: Int64(data.count), builtAt: Date(timeIntervalSince1970: 0))
    }

    private func manifest(_ blocks: [StoreManifest.Block], profile: String = "full") throws -> StoreManifest {
        let format = try FeatureStoreFile(
            data: FeatureStoreWriter(boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: "").data()
        ).formatVersion
        let manifest = StoreManifest(
            formatVersion: format, classifierVersion: 16, storageZoom: 13, blockZoom: 8, bands: bands,
            profile: profile, attribution: attribution, blocks: blocks)
        try manifest.validate()
        return manifest
    }

    private func source(_ id: String = "denmark") -> [StoreManifest.Source] {
        [StoreManifest.Source(regionID: id, url: "https://example.org/\(id).pbf", size: 1, downloadedAt: Date(timeIntervalSince1970: 0))]
    }

    private func covered(_ positions: [Position]) -> [Position: [StoreManifest.Source]] {
        Dictionary(uniqueKeysWithValues: positions.map { ($0, source()) })
    }

    @Test func aBlockWithNoFileNextToSeaBecomesSea() throws {
        let folder = try folder()
        let seaBlock = Position(x: 10, y: 10), open = Position(x: 11, y: 10)
        let before = try manifest([write(.sea, at: seaBlock, in: folder)])
        let (after, report) = try OpenSea.fill(manifest: before, folder: folder, covered: covered([seaBlock, open]))
        #expect(report.created == [open] && report.extended.isEmpty && report.left.isEmpty)
        try after.validate()
        let block = try #require(after.blocks.first { $0.x == 11 })
        #expect(block.sources == source())
        let file = try FeatureStoreFile(contentsOf: folder.appendingPathComponent(block.file))
        try file.verify()
        #expect(Int64(try Data(contentsOf: folder.appendingPathComponent(block.file)).count) == block.bytes)
        #expect(try file.cells().count == 1024)
        // Every cell has its square in every band (the reader takes the band from the manifest, not from the file).
        for cell in [cells(of: open)[0], cells(of: open)[500], cells(of: open)[1023]] {
            for band in bands {
                let found = try file.features(in: cell, band: band)
                #expect(found.count == 1 && found[0].classID == FeatureClass.sea.rawValue)
                #expect(found[0].parts == [SeaBuilder.wholeCell(CellRect(tile: cell))])
            }
        }
    }

    @Test func aGroupOfBlocksIsFilledThroughTheBlocksBetween() throws {
        let folder = try folder()
        let seaBlock = Position(x: 10, y: 10)
        let group = [Position(x: 11, y: 10), Position(x: 12, y: 10), Position(x: 12, y: 11)]
        let before = try manifest([write(.sea, at: seaBlock, in: folder)])
        let (after, report) = try OpenSea.fill(manifest: before, folder: folder, covered: covered([seaBlock] + group))
        #expect(Set(report.created) == Set(group))
        #expect(after.blocks.count == 4)
    }

    @Test func aBlockOutsideTheSourceCoverageStaysEmpty() throws {
        let folder = try folder()
        let seaBlock = Position(x: 10, y: 10)
        let before = try manifest([write(.sea, at: seaBlock, in: folder)])
        let (after, report) = try OpenSea.fill(manifest: before, folder: folder, covered: covered([seaBlock]))
        #expect(!report.changed && after == before)
    }

    @Test func aGroupThatOnlyTouchesLandOrNothingIsLeft() throws {
        let folder = try folder()
        let landBlock = Position(x: 10, y: 10), inland = Position(x: 11, y: 10), alone = Position(x: 20, y: 20)
        let before = try manifest([write(.land, at: landBlock, in: folder)])
        let (after, report) = try OpenSea.fill(manifest: before, folder: folder, covered: covered([landBlock, inland, alone]))
        #expect(!report.changed && after == before)
        #expect(Set(report.left) == [inland, alone] && report.conflicting.isEmpty)
    }

    @Test func aGroupBetweenSeaAndLandIsLeftAndReported() throws {
        let folder = try folder()
        let seaBlock = Position(x: 10, y: 10), landBlock = Position(x: 12, y: 10), middle = Position(x: 11, y: 10)
        let before = try manifest([write(.sea, at: seaBlock, in: folder), write(.land, at: landBlock, in: folder)])
        let (after, report) = try OpenSea.fill(manifest: before, folder: folder, covered: covered([seaBlock, middle, landBlock]))
        #expect(!report.changed && after == before)
        #expect(report.conflicting == [middle])
    }

    @Test func aSparseBlockKeepsItsFeaturesNamesAndRelationsAndGetsTheSea() throws {
        let folder = try folder()
        let seaBlock = Position(x: 10, y: 10), sparse = Position(x: 11, y: 10)
        let before = try manifest([write(.sea, at: seaBlock, in: folder), write(.sparse, at: sparse, in: folder)])
        let old = try #require(before.blocks.first { $0.x == 11 })
        let (after, report) = try OpenSea.fill(manifest: before, folder: folder, covered: covered([seaBlock, sparse]))
        #expect(report.extended == [sparse] && report.created.isEmpty)
        let block = try #require(after.blocks.first { $0.x == 11 })
        #expect(block.file == old.file && block.bytes != old.bytes && block.sources == old.sources)
        let file = try FeatureStoreFile(contentsOf: folder.appendingPathComponent(block.file))
        try file.verify()
        #expect(Int64(try Data(contentsOf: folder.appendingPathComponent(block.file)).count) == block.bytes)
        let cell = cells(of: sparse)[100]
        for band in bands {
            let found = try file.features(in: cell, band: band)
            #expect(found.count == 2)
            let border = try #require(found.first { $0.classID == FeatureClass.countryBorder.rawValue })
            #expect(border.nameID.flatMap { file.string(at: $0) } == "Grensen")
            #expect(border.tags.map { [file.string(at: $0.key), file.string(at: $0.value)] } == [["boundary", "administrative"]])
            #expect(found.contains { $0.classID == FeatureClass.sea.rawValue })
        }
        let relation = try #require(try file.relation(withID: 99))
        #expect(relation.members.count == 1 && file.string(at: relation.members[0].role) == "outer")
        #expect(file.string(at: relation.tags[0].key) == "boundary")
        // A cell with nothing before has the square now.
        #expect(try file.features(in: cells(of: sparse)[0], band: .detail).count == 1)
    }

    @Test func aSecondRunChangesNothing() throws {
        let folder = try folder()
        let seaBlock = Position(x: 10, y: 10), open = Position(x: 11, y: 10), sparse = Position(x: 9, y: 10)
        let before = try manifest([write(.sea, at: seaBlock, in: folder), write(.sparse, at: sparse, in: folder)])
        let all = covered([seaBlock, open, sparse])
        let (first, report) = try OpenSea.fill(manifest: before, folder: folder, covered: all)
        #expect(report.created == [open] && report.extended == [sparse])
        let (second, again) = try OpenSea.fill(manifest: first, folder: folder, covered: all)
        #expect(!again.changed && second == first)
    }

    @Test func theWatchProfileIsLeftAlone() throws {
        let folder = try folder()
        let seaBlock = Position(x: 10, y: 10), open = Position(x: 11, y: 10)
        let before = try manifest([write(.sea, at: seaBlock, in: folder)], profile: "watch")
        let (after, report) = try OpenSea.fill(manifest: before, folder: folder, covered: covered([seaBlock, open]))
        #expect(!report.changed && after == before)
    }

    @Test func aBorderWithAPartialSeaCellIsUnclearAndTheGroupIsLeft() throws {
        let folder = try folder()
        let seaBlock = Position(x: 10, y: 10), open = Position(x: 11, y: 10)
        // A sea block whose east edge has one cell that is only part sea.
        var writer = FeatureStoreWriter(
            boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: attribution, classifierVersion: 16)
        let all = cells(of: seaBlock)
        for cell in all { for band in bands { try writer.add(seaSquare(cell), band: band, cell: cell) } }
        try writer.add(coastline(all[0]), band: .overview, cell: all[0])
        let edge = all[31]    // the east edge of the first row
        let rect = CellRect(tile: edge)
        var part = StoredFeature(
            classID: FeatureClass.sea.rawValue, kind: .area, objectType: .way, objectID: 0,
            parts: [GeometryPart(points: [
                PackedPoint(longitude: rect.west, latitude: rect.north), PackedPoint(longitude: rect.east, latitude: rect.north),
                PackedPoint(longitude: rect.west, latitude: rect.south), PackedPoint(longitude: rect.west, latitude: rect.north),
            ])])
        part.flags = []
        var broken = FeatureStoreWriter(
            boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1), attribution: attribution, classifierVersion: 16)
        for cell in all where cell != edge { for band in bands { try broken.add(seaSquare(cell), band: band, cell: cell) } }
        for band in bands { try broken.add(part, band: band, cell: edge) }
        try broken.add(coastline(all[0]), band: .overview, cell: all[0])
        let name = "blocks/8-10-10.gmk"
        let data = try broken.data()
        try data.write(to: folder.appendingPathComponent(name))
        let before = try manifest([StoreManifest.Block(x: 10, y: 10, file: name, bytes: Int64(data.count), builtAt: Date(timeIntervalSince1970: 0))])
        let (after, report) = try OpenSea.fill(manifest: before, folder: folder, covered: covered([seaBlock, open]))
        #expect(!report.changed && after == before && report.left == [open] && report.conflicting.isEmpty)
    }

    @Test func aBlockThatOnlyTouchesSeaAtACornerIsLeft() throws {
        let folder = try folder()
        let seaBlock = Position(x: 10, y: 10), diagonal = Position(x: 11, y: 11)
        let before = try manifest([write(.sea, at: seaBlock, in: folder)])
        let (_, report) = try OpenSea.fill(manifest: before, folder: folder, covered: covered([seaBlock, diagonal]))
        #expect(!report.changed && report.left == [diagonal])
    }

    @Test func aBlockThatCannotBeReadIsNeverReplaced() throws {
        let folder = try folder()
        let seaBlock = Position(x: 10, y: 10), sparse = Position(x: 11, y: 10)
        let good = try write(.sea, at: seaBlock, in: folder)
        var bad = try write(.sparse, at: sparse, in: folder)
        let url = folder.appendingPathComponent(bad.file)
        try Data("not a store file".utf8).write(to: url)
        bad.bytes = 16
        let before = try manifest([good, bad])
        #expect(throws: (any Error).self) { try OpenSea.fill(manifest: before, folder: folder, covered: covered([seaBlock, sparse])) }
        #expect(try Data(contentsOf: url) == Data("not a store file".utf8))
    }

    @Test func theManifestIsPersistedAfterEachBlockAndTheTimeIsInjected() throws {
        let folder = try folder()
        let seaBlock = Position(x: 10, y: 10), a = Position(x: 11, y: 10), b = Position(x: 9, y: 10)
        let before = try manifest([write(.sea, at: seaBlock, in: folder)])
        let moment = Date(timeIntervalSince1970: 1_000_000)
        var saved: [Int] = []
        let (after, _) = try OpenSea.fill(manifest: before, folder: folder, covered: covered([seaBlock, a, b]), now: moment) { saved.append($0.blocks.count) }
        #expect(saved == [2, 3])
        #expect(after.blocks.filter { $0.builtAt == moment }.count == 2)
    }
}
