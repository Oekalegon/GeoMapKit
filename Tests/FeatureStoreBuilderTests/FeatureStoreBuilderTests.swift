import FeatureStore
import Foundation
import GeoCore
import OSMPBF
import Testing

@testable import FeatureStoreBuilder

/// The synthetic world through the cut, the builder and the reader.
@Suite("Feature store builder")
struct FeatureStoreBuilderTests {
    private func built(_ profile: BuildProfile = .full) throws -> (file: FeatureStoreFile, result: BuildResult, world: SyntheticWorld, extract: OSMExtract) {
        var world = SyntheticWorld.standard()
        let extract = try world.extract()
        let result = try FeatureStoreBuilder(profile: profile).build(from: extract)
        return (try FeatureStoreFile(data: result.data), result, world, extract)
    }

    private func features(_ file: FeatureStoreFile, band: ZoomBand = .detail) throws -> [(cell: TileID, feature: StoredFeature)] {
        try file.cells().flatMap { cell in try file.features(in: cell, band: band).map { (cell, $0) } }
    }

    private func pairs(_ feature: StoredFeature, _ file: FeatureStoreFile) -> [[[UInt8]]] {
        feature.tags.map { [Array(file.stringBytes(at: $0.key) ?? Data()), Array(file.stringBytes(at: $0.value) ?? Data())] }
    }

    private func pieces(_ all: [(cell: TileID, feature: StoredFeature)], type: StoredObjectType, id: Int64) -> [(cell: TileID, feature: StoredFeature)] {
        all.filter { $0.feature.objectType == type && $0.feature.objectID == id }
    }

    @Test("The file is valid, carries the attribution and covers the nine cells of the block")
    func header() throws {
        let (file, result, world, _) = try built()
        try file.verify()
        #expect(file.attribution == FeatureStoreBuilder.attribution)
        #expect(file.classifierVersion == Int(FeatureClassifier.version))
        #expect(file.storageZoom == 13)
        #expect(file.bands == [.overview, .mid, .detail])
        #expect(result.report.cellsInArea == 9)
        let tiles = try file.cells()
        #expect(tiles.count <= 9 && !tiles.isEmpty)
        #expect(tiles.allSatisfy { (world.block.centre.x - 1...world.block.centre.x + 1).contains($0.x) && (world.block.centre.y - 1...world.block.centre.y + 1).contains($0.y) })
    }

    @Test("The report counts what was stored, suppressed and skipped")
    func report() throws {
        let report = try built().result.report
        #expect(report.nodesStored == 6)
        #expect(report.waysStored == 8)                 // 100, 101, 200, 700, 800, 900, 1000, 1001
        #expect(report.waysSuppressed == 5)             // 301, 302, 401, 451 (untagged members) and 501 (tags adopted)
        #expect(report.waysWithMissingNodes == 1 && report.waysWithoutGeometry == 0)
        #expect(report.relationsStored == 5)
        #expect(report.multipolygonsAssembled == 2 && report.polygons == 2)
        #expect(report.multipolygonsIncomplete == 2)
        #expect(report.unclosedChains == 2 && report.missingMembers == 1)
        #expect(report.piecesOutsideCells >= 2)         // node 4 and the end of way 101
        #expect(report.featuresSkippedByProfile == 0)
    }

    @Test("A tagged node becomes a point in the right cell with its class and all tags")
    func points() throws {
        let (file, _, world, _) = try built()
        let all = try features(file)
        let peak = try #require(pieces(all, type: .node, id: 1).first)
        #expect(peak.cell == world.block.centre)
        #expect(peak.feature.kind == .point && peak.feature.classID == FeatureClass.peak.rawValue)
        #expect(file.string(at: try #require(peak.feature.nameID)) == "Test Peak")
        #expect(peak.feature.parts[0].points == [world.block.point(1.5, 1.5)])
        #expect(pairs(peak.feature, file).contains([Array("natural".utf8), Array("peak".utf8)]))
        // The node outside the written cells is not stored.
        #expect(pieces(all, type: .node, id: 4).isEmpty)
    }

    @Test("Two tag keys that differ only in Unicode normalization are both stored, byte for byte")
    func equivalentKeys() throws {
        let (file, _, _, _) = try built()
        let node = try #require(pieces(try features(file), type: .node, id: 3).first)
        let keys = pairs(node.feature, file).map { $0[0] }
        #expect(keys.count == 2)
        #expect(Set(keys) == [Array(SyntheticWorld.precomposed.utf8), Array(SyntheticWorld.decomposed.utf8)])
    }

    @Test("A path across cell borders is stored as pieces that chain, with class, subclass, flags and offsets")
    func linePieces() throws {
        let (file, _, world, extract) = try built()
        let path = pieces(try features(file), type: .way, id: 100).sorted { $0.feature.offsetAlongLine < $1.feature.offsetAlongLine }
        #expect(path.count == 3)
        #expect(path.map(\.cell.x) == [world.block.centre.x - 1, world.block.centre.x, world.block.centre.x + 1])
        #expect(path.allSatisfy { $0.feature.classID == FeatureClass.path.rawValue && $0.feature.subclass == 1 })
        #expect(path.map(\.feature.flags) == [[.continuesAfter], [.continuesBefore, .continuesAfter], [.continuesBefore]])
        #expect(path[0].feature.parts[0].points.last == path[1].feature.parts[0].points.first)
        #expect(path[1].feature.parts[0].points.last == path[2].feature.parts[0].points.first)
        // Every original vertex is stored, and the pieces add up to the original length.
        let original = extract.ways.nodeIDs(at: try #require(extract.ways.index(ofID: 100))).compactMap { extract.nodes.index(ofID: $0) }
            .map { FeatureStoreBuilder.packed(extract.nodes.coordinate(at: $0)) }
        let stored = path.flatMap { $0.feature.parts[0].points }
        #expect(original.allSatisfy { stored.contains($0) })
        #expect(abs(path.reduce(0) { $0 + length($1.feature.parts[0].points) } - length(original)) < 1)
        #expect(file.string(at: try #require(path[0].feature.nameID)) == "Rheinweg")
        // Paths start at the mid band: absent from overview, present in mid with the name but no tags.
        #expect(pieces(try features(file, band: .overview), type: .way, id: 100).isEmpty)
        let mid = pieces(try features(file, band: .mid), type: .way, id: 100)
        #expect(!mid.isEmpty && mid.allSatisfy { $0.feature.tags.isEmpty && $0.feature.nameID != nil })
        // The forest starts at the overview band and is in all three.
        for band in ZoomBand.allCases { #expect(!pieces(try features(file, band: band), type: .way, id: 200).isEmpty) }
    }

    @Test("A way that leaves the written cells loses only the part outside, and the rest is counted")
    func leavesWrittenCells() throws {
        let (file, result, _, _) = try built()
        let outside = pieces(try features(file), type: .way, id: 101)
        #expect(outside.count == 1 && outside[0].feature.flags == [.continuesAfter])
        #expect(result.report.piecesOutsideCells >= 2)
    }

    @Test("A forest across a border is two area pieces with an artificial edge on the border, and the area adds up")
    func areaPieces() throws {
        let (file, _, _, extract) = try built()
        let forest = pieces(try features(file), type: .way, id: 200)
        #expect(forest.count == 2 && forest.allSatisfy { $0.feature.kind == .area && $0.feature.classID == FeatureClass.forest.rawValue })
        #expect(forest.allSatisfy { !$0.feature.parts[0].artificialEdges.isEmpty })
        let original = extract.ways.nodeIDs(at: try #require(extract.ways.index(ofID: 200))).compactMap { extract.nodes.index(ofID: $0) }
            .map { FeatureStoreBuilder.packed(extract.nodes.coordinate(at: $0)) }
        let total = forest.reduce(0) { $0 + projectedArea($1.feature.parts[0].points) }
        #expect(abs(total - projectedArea(original)) < projectedArea(original) * 1e-4)
    }

    @Test("A multipolygon with a hole is one area feature per cell, the hole is a second ring, and the area adds up")
    func multipolygonWithHole() throws {
        let (file, result, world, extract) = try built()
        let lake = pieces(try features(file), type: .relation, id: 300)
        #expect(lake.count == 3 && lake.allSatisfy { $0.feature.kind == .area && $0.feature.classID == FeatureClass.waterArea.rawValue })
        let middle = try #require(lake.first { $0.cell.x == world.block.centre.x })
        #expect(middle.feature.parts.count == 2)
        #expect(file.string(at: try #require(middle.feature.nameID)) == "Lake")
        // Even-odd: the pieces of the outer ring minus the hole equal the polygon's area.
        func ring(_ id: Int64) throws -> [PackedPoint] {
            try extract.ways.nodeIDs(at: try #require(extract.ways.index(ofID: id))).compactMap { extract.nodes.index(ofID: $0) }
                .map { FeatureStoreBuilder.packed(extract.nodes.coordinate(at: $0)) }
        }
        let expected = projectedArea(try ring(301)) - projectedArea(try ring(302))
        var outerPieces = 0.0, holePieces = 0.0
        for piece in lake {
            for part in piece.feature.parts {
                // The hole lies in one cell only, and its ring is the smaller of the two there.
                if piece.feature.parts.count == 2, part == piece.feature.parts.min(by: { projectedArea($0.points) < projectedArea($1.points) }) {
                    holePieces += projectedArea(part.points)
                } else {
                    outerPieces += projectedArea(part.points)
                }
            }
        }
        #expect(abs((outerPieces - holePieces) - expected) < expected * 1e-4)
        #expect(result.report.polygons == 2)
    }

    @Test("A multipolygon that cannot be assembled is stored as outlines with the incomplete flag, never as an area")
    func incompleteMultipolygon() throws {
        let (file, _, _, _) = try built()
        let outline = pieces(try features(file), type: .relation, id: 400)
        #expect(!outline.isEmpty)
        #expect(outline.allSatisfy { $0.feature.kind == .line && $0.feature.flags.contains(.incomplete) })
        #expect(outline.allSatisfy { $0.feature.classID == FeatureClass.landcover.rawValue })
        #expect(try features(file).allSatisfy { !($0.feature.kind == .area && $0.feature.flags.contains(.incomplete)) })
    }

    @Test("An old-style multipolygon takes the tags of its outer way, and that way is not stored twice")
    func oldStyle() throws {
        let (file, _, _, _) = try built()
        let all = try features(file)
        let area = try #require(pieces(all, type: .relation, id: 500).first)
        #expect(area.feature.kind == .area && area.feature.classID == FeatureClass.landcover.rawValue)
        #expect(pairs(area.feature, file).contains([Array("landuse".utf8), Array("farmland".utf8)]))
        #expect(pieces(all, type: .way, id: 501).isEmpty)
        // Untagged member ways of assembled multipolygons are not stored on their own either.
        for id: Int64 in [301, 302, 401, 451] { #expect(pieces(all, type: .way, id: id).isEmpty) }
    }

    @Test("Untagged ways outside relations, ways with gaps and buildings are stored")
    func otherWays() throws {
        let (file, _, _, _) = try built()
        let all = try features(file)
        let untagged = try #require(pieces(all, type: .way, id: 700).first)
        #expect(untagged.feature.classID == FeatureClass.other.rawValue && untagged.feature.tags.isEmpty && untagged.feature.kind == .line)
        let gaps = pieces(all, type: .way, id: 800)
        #expect(gaps.count == 2 && gaps.allSatisfy { $0.feature.classID == FeatureClass.track.rawValue && $0.feature.subclass == 2 })
        #expect(pieces(all, type: .way, id: 900).first?.feature.classID == FeatureClass.building.rawValue)
    }

    @Test("Every relation is in the relation table with all tags and members, whatever its type")
    func relationTable() throws {
        let (file, _, _, extract) = try built()
        for relation in extract.relations {
            let stored = try #require(try file.relation(withID: relation.relation.id))
            #expect(stored.members.count == relation.relation.members.count)
            #expect(stored.isIncomplete == !relation.isComplete)
            #expect(stored.tags.count == relation.relation.orderedTags.count)
            for (tag, original) in zip(stored.tags, relation.relation.orderedTags) {
                #expect(file.stringBytes(at: tag.key).map(Array.init) == Array(original.key.utf8))
                #expect(file.stringBytes(at: tag.value).map(Array.init) == Array(original.value.utf8))
            }
            for (member, original) in zip(stored.members, relation.relation.members) {
                #expect(member.id == original.id && member.role < UInt32(file.stringTableCount))
                #expect(file.string(at: member.role) == original.role)
            }
        }
        let route = try #require(try file.relation(withID: 600))
        #expect(route.members.map(\.type) == [.way, .node])
        #expect(try file.relation(withID: 450)?.isIncomplete == true)
    }

    @Test("The watch copy has the flagged classes, no overview band, only names, and no relation table")
    func watchProfile() throws {
        let (full, fullResult, _, _) = try built()
        let (watch, watchResult, _, _) = try built(.watch)
        try watch.verify()
        #expect(watch.bands == [.mid, .detail])
        let all = try features(watch)
        #expect(all.allSatisfy { $0.feature.tags.isEmpty })
        let classes = Set(all.map(\.feature.classID))
        #expect(classes.isSubset(of: [FeatureClass.path, .track, .forest, .peak, .waterArea, .landcover, .poiAnchor, .powerLine, .piste, .aerialway].map(\.rawValue)))
        #expect(!classes.contains(FeatureClass.building.rawValue) && !classes.contains(FeatureClass.poi.rawValue) && !classes.contains(FeatureClass.other.rawValue))
        #expect(try watch.relation(withID: 600) == nil && watchResult.report.relationsStored == 0)
        #expect(watchResult.report.featuresSkippedByProfile > 0)
        #expect(watch.stringTableCount < full.stringTableCount)
        #expect(watchResult.data.count < fullResult.data.count)
        // Power lines and pistes are on the Watch, trees are not.
        #expect(pieces(all, type: .way, id: 1000).first?.feature.classID == FeatureClass.powerLine.rawValue)
        #expect(pieces(all, type: .way, id: 1001).first?.feature.classID == FeatureClass.piste.rawValue)
        #expect(pieces(all, type: .node, id: 6).isEmpty)
        let fullPieces = pieces(try features(full), type: .node, id: 6)
        #expect(fullPieces.first?.feature.classID == FeatureClass.tree.rawValue)
        // The names survive.
        let peak = try #require(pieces(all, type: .node, id: 1).first)
        #expect(watch.string(at: try #require(peak.feature.nameID)) == "Test Peak")
        // Everything the watch copy holds is also in the full copy, with the same geometry.
        let fullAll = try features(full)
        for item in all {
            #expect(fullAll.contains { $0.cell == item.cell && $0.feature.objectID == item.feature.objectID && $0.feature.parts == item.feature.parts })
        }
    }

    @Test("The same extract always gives the same bytes")
    func deterministic() throws {
        #expect(try built().result.data == built().result.data)
    }

    @Test("Statistics add up")
    func statistics() throws {
        let (file, _, _, _) = try built()
        let stats = try file.statistics()
        #expect(stats.cellCount == (try file.cells()).count)
        for band in ZoomBand.allCases {
            #expect(stats.featureCounts[band] == (try features(file, band: band)).count)
        }
        #expect(stats.detailFeaturesByClass.values.reduce(0, +) == stats.featureCounts[.detail])
        #expect(stats.fileBytes == (try built()).result.data.count)
        #expect((stats.featureCounts[.detail] ?? 0) >= (stats.featureCounts[.mid] ?? 0))
    }

    @Test("A box smaller than one cell gives an empty but valid store")
    func tinyBox() throws {
        var world = SyntheticWorld.standard()
        let tiny = BoundingBox(south: 47.14, west: 9.52, north: 47.1401, east: 9.5201)
        let extract = try AreaCutter().cut(try PBFReader(data: world.file()), to: tiny)
        let result = try FeatureStoreBuilder().build(from: extract)
        let file = try FeatureStoreFile(data: result.data)
        try file.verify()
        #expect(file.cellCount == 0 && result.report.cellsInArea == 0)
    }

    @Test("Cancellation stops the build")
    func cancellation() async throws {
        var world = SyntheticWorld.standard()
        let extract = try world.extract()
        let task = Task { () throws -> BuildResult in
            withUnsafeCurrentTask { $0?.cancel() }
            return try FeatureStoreBuilder().build(from: extract)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
