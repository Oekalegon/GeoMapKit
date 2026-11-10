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
        // Paths start at the mid band: absent from overview, present in mid with the name and only the tags a style selects by (`KeptTagsTests`).
        #expect(pieces(try features(file, band: .overview), type: .way, id: 100).isEmpty)
        let mid = pieces(try features(file, band: .mid), type: .way, id: 100)
        #expect(!mid.isEmpty && mid.allSatisfy { piece in
            piece.feature.nameID != nil && piece.feature.tags.allSatisfy { FeatureEmitter.keptTags[.path]?.contains(file.string(at: $0.key) ?? "") == true }
        })
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
        // The outline of the lake is stored with it, as lines of class `waterEdge`; the area itself is what is counted here.
        let lake = pieces(try features(file), type: .relation, id: 300).filter { $0.feature.classID == FeatureClass.waterArea.rawValue }
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

    @Test("A coastline across the block becomes a sea polygon in the cells south of it, and nothing north of it")
    func sea() throws {
        var world = SyntheticWorld()
        world.node(1, -0.3, 1.5); world.node(2, 1.5, 1.4); world.node(3, 3.3, 1.5)
        world.way(10, [1, 2, 3], [("natural", "coastline")])
        let extract = try world.extract()
        let result = try FeatureStoreBuilder().build(from: extract)
        let file = try FeatureStoreFile(data: result.data)
        try file.verify()
        #expect(result.report.coastlineWays == 1 && result.report.seaPolygons == 1 && result.report.seaOpenEnds == 0)
        #expect(result.report.featuresByClass[.sea] == 1 && result.report.featuresByClass[.coastline] == 1)
        let block = world.block
        for band in ZoomBand.allCases {
            for row in 0..<3 {
                for column in 0..<3 {
                    let cell = block.tile(column: column, row: row)
                    let seaPieces = try file.features(in: cell, band: band).filter { $0.classID == FeatureClass.sea.rawValue }
                    // The coast is at y = 1.5: row 0 is land, row 2 is sea, row 1 is both.
                    if row == 0 { #expect(seaPieces.isEmpty, "land in \(band) \(column),\(row)") }
                    if row >= 1 { #expect(seaPieces.count == 1 && seaPieces[0].kind == .area, "sea in \(band) \(column),\(row)") }
                }
            }
        }
        // A cell wholly in the sea is covered completely: its piece is the cell square, with every edge artificial.
        let southCell = block.tile(column: 1, row: 2)
        let piece = try #require(try file.features(in: southCell, band: .detail).first { $0.classID == FeatureClass.sea.rawValue })
        #expect(piece.parts.count == 1 && piece.parts[0].points.count == 5)
    }

    @Test("A coastline that ends inside the area builds no sea, and the report says so")
    func brokenCoastline() throws {
        var world = SyntheticWorld()
        world.node(1, 0.5, 1.5); world.node(2, 1.5, 1.4)
        world.way(10, [1, 2], [("natural", "coastline")])
        let extract = try world.extract()
        let result = try FeatureStoreBuilder().build(from: extract)
        #expect(result.report.seaOpenEnds > 0 && result.report.seaPolygons == 0 && result.report.featuresByClass[.sea] == nil)
        #expect(result.report.featuresByClass[.coastline] == 1)
    }

    @Test("An island mapped as a multipolygon of a coastline way gets its shore as a line, not as an area")
    func coastlineRelation() throws {
        var world = SyntheticWorld()
        let ring = world.rectangle(first: 1, 1.2, 1.2, 1.8, 1.8)
        world.way(10, ring, [("natural", "coastline")])
        world.relation(20, [(10, "outer", 1)], [("type", "multipolygon")])
        let extract = try world.extract()
        let result = try FeatureStoreBuilder().build(from: extract)
        let file = try FeatureStoreFile(data: result.data)
        let all = try file.cells().flatMap { try file.features(in: $0, band: .detail) }
        let shore = all.filter { $0.classID == FeatureClass.coastline.rawValue }
        #expect(!shore.isEmpty && shore.allSatisfy { $0.kind == .line }, "the shore is a line")
        #expect(shore.allSatisfy { $0.objectType == .relation && $0.objectID == 20 })
        #expect(!all.contains { $0.classID == FeatureClass.coastline.rawValue && $0.kind == .area })
    }

    @Test("The Watch copy has the sea in the mid and detail bands only")
    func seaInTheWatchCopy() throws {
        var world = SyntheticWorld()
        world.node(1, -0.3, 1.5); world.node(2, 1.5, 1.4); world.node(3, 3.3, 1.5)
        world.way(10, [1, 2, 3], [("natural", "coastline")])
        let result = try FeatureStoreBuilder(profile: .watch).build(from: try world.extract())
        let file = try FeatureStoreFile(data: result.data)
        let block = world.block
        let cell = block.tile(column: 1, row: 2)
        #expect(file.bands == [.mid, .detail])
        for band in [ZoomBand.mid, .detail] {
            #expect(try file.features(in: cell, band: band).contains { $0.classID == FeatureClass.sea.rawValue }, "sea in \(band)")
        }
        #expect(result.report.seaPolygons == 1)
    }

    @Test("A coastline way with a node missing from the file builds no sea, and the report says so")
    func brokenCoastlineWay() throws {
        var world = SyntheticWorld()
        world.node(1, -0.3, 1.5); world.node(3, 3.3, 1.5)
        world.way(10, [1, 999, 3], [("natural", "coastline")])      // node 999 is not in the file
        let result = try FeatureStoreBuilder().build(from: try world.extract())
        #expect(result.report.seaOpenEnds > 0 && result.report.seaPolygons == 0 && result.report.featuresByClass[.sea] == nil)
    }

    @Test("Every street and the buildings are in the mid band, the Watch copy has the streets but no house")
    func streetsAndBuildingsInTheMidBand() throws {
        var world = SyntheticWorld()
        world.node(1, 0.3, 1.5); world.node(2, 2.7, 1.5)
        world.way(100, [1, 2], [("highway", "residential"), ("name", "Storgata")])
        world.node(3, 0.3, 1.2); world.node(4, 2.7, 1.2)
        world.way(101, [3, 4], [("highway", "service")])
        let house = world.rectangle(first: 10, 1.0, 1.7, 1.2, 1.9)
        world.way(200, house, [("building", "yes")])
        // A shed of a couple of metres, which simplification for the mid band cannot keep.
        world.node(20, 2.0, 2.0); world.node(21, 2.0004, 2.0); world.node(22, 2.0004, 2.0004); world.node(23, 2.0, 2.0004)
        world.way(201, [20, 21, 22, 23, 20], [("building", "yes")])
        let extract = try world.extract()
        func ids(_ file: FeatureStoreFile, _ band: ZoomBand) throws -> Set<Int64> {
            Set(try file.cells().flatMap { try file.features(in: $0, band: band) }.map(\.objectID))
        }
        let full = try FeatureStoreBuilder().build(from: extract)
        let file = try FeatureStoreFile(data: full.data)
        let mid = try ids(file, .mid), detail = try ids(file, .detail), overview = try ids(file, .overview)
        #expect(mid.contains(100) && mid.contains(200), "the street and the house are in the mid band")
        #expect(mid.contains(101) && detail.contains(101), "a service road is in the mid band with the paths")
        #expect(detail.contains(201) && !mid.contains(201), "a shed is in the detail band; the mid band could not keep it")
        #expect(full.report.ringsTooSmallForMid >= 1)
        #expect(!overview.contains(100) && !overview.contains(200), "nothing of the two in the overview band")
        let watch = try FeatureStoreBuilder(profile: .watch).build(from: extract)
        let watchFile = try FeatureStoreFile(data: watch.data)
        let watchMid = try ids(watchFile, .mid)
        #expect(watchMid.contains(100) && watchMid.contains(101), "the Watch copy has the streets in its mid band")
        let watchDetail = try ids(watchFile, .detail)
        #expect(!watchMid.contains(200) && !watchDetail.contains(200), "and no house")
    }

    @Test("Urban land use and the large land cover are in the overview band, small land cover starts at the mid band")
    func landUseInTheOverviewBand() throws {
        var world = SyntheticWorld()
        world.way(10, world.rectangle(first: 10, 0.3, 0.3, 1.3, 1.3), [("landuse", "residential")])
        world.way(11, world.rectangle(first: 20, 1.6, 0.3, 2.6, 1.3), [("landuse", "farmland")])
        world.way(12, world.rectangle(first: 30, 0.3, 1.6, 1.3, 2.6), [("natural", "heath")])
        world.way(13, world.rectangle(first: 40, 1.6, 1.6, 2.6, 2.6), [("landuse", "grass")])
        let extract = try world.extract()
        func ids(_ file: FeatureStoreFile, _ band: ZoomBand) throws -> Set<Int64> {
            Set(try file.cells().flatMap { try file.features(in: $0, band: band) }.map(\.objectID))
        }
        let file = try FeatureStoreFile(data: try FeatureStoreBuilder().build(from: extract).data)
        let overview = try ids(file, .overview), mid = try ids(file, .mid)
        #expect(overview.isSuperset(of: [10, 11, 12]), "a village, a field and heath are in the overview band")
        #expect(!overview.contains(13) && mid.contains(13), "a lawn starts at the mid band")
        let watch = try FeatureStoreFile(data: try FeatureStoreBuilder(profile: .watch).build(from: extract).data)
        #expect(try ids(watch, .mid).isSuperset(of: [11, 12, 13]), "the Watch copy has them in its mid band")
    }

    @Test("A coastline that leaves the extract at a country border still gets its sea; one that just stops does not")
    func coastlineAtTheBorder() throws {
        func build(withBorder: Bool) throws -> BuildReport {
            var world = SyntheticWorld()
            world.node(1, -0.3, 1.5); world.node(2, 0.8, 1.45); world.node(3, 1.5, 1.4)
            world.way(10, [1, 2, 3], [("natural", "coastline")])
            if withBorder {
                world.node(4, 1.52, 1.3); world.node(5, 1.52, 1.6)
                world.way(20, [4, 5], [("boundary", "administrative"), ("admin_level", "2")])
            }
            return try FeatureStoreBuilder().build(from: try world.extract()).report
        }
        let withBorder = try build(withBorder: true)
        #expect(withBorder.seaEndsExtended == 1 && withBorder.seaPolygons == 1 && withBorder.seaOpenEnds == 0)
        let without = try build(withBorder: false)
        #expect(without.seaEndsExtended == 0 && without.seaPolygons == 0 && without.seaOpenEnds > 0)
    }

    @Test("A way left out for a missing node does not stop the sea of the rest of the area")
    func skippedWayFarAway() throws {
        var world = SyntheticWorld()
        world.node(1, -0.3, 1.5); world.node(2, 3.3, 1.5)
        world.way(10, [1, 2], [("natural", "coastline")])
        // A coastline way with a node that is not in the file, near the corner of the cut box.
        world.node(3, 3.4, 3.4); world.node(4, 3.45, 3.45)
        world.way(11, [3, 999, 4], [("natural", "coastline")])
        let result = try FeatureStoreBuilder().build(from: try world.extract())
        #expect(result.report.coastlineWaysSkipped == 1 && result.report.seaPolygons == 1 && result.report.seaOpenEnds == 0)
    }

    // MARK: A part of the extract

    /// A feature without the numbers that belong to its file: its names and tags as text.
    private struct Plain: Hashable {
        var classID: UInt8, subclass: UInt8, kind: FeatureKind, type: StoredObjectType, id: Int64, flags: FeatureFlags, offset: UInt32
        var name: String?, tags: [[String]], parts: [GeometryPart]
    }

    private func plain(_ feature: StoredFeature, _ file: FeatureStoreFile) -> Plain {
        Plain(
            classID: feature.classID, subclass: feature.subclass, kind: feature.kind, type: feature.objectType, id: feature.objectID,
            flags: feature.flags, offset: feature.offsetAlongLine, name: feature.nameID.flatMap { file.string(at: $0) },
            tags: feature.tags.map { [file.string(at: $0.key) ?? "", file.string(at: $0.value) ?? ""] }, parts: feature.parts)
    }

    @Test("Building a part of the extract gives the cells of that part as the whole build has them, and no others")
    func partOfTheExtract() throws {
        var world = SyntheticWorld.standard()
        let extract = try world.extract()
        let builder = FeatureStoreBuilder()
        let whole = try FeatureStoreFile(data: try builder.build(from: extract).data)
        // The two western columns of the block: the cells with x below the centre column.
        let centre = world.block.centre
        let west = TileID(zoom: 13, x: centre.x - 1, y: centre.y - 1)!, east = TileID(zoom: 13, x: centre.x, y: centre.y + 1)!
        let part = BoundingBox(south: east.southEast.latitude, west: west.northWest.longitude, north: west.northWest.latitude, east: east.southEast.longitude)
        let partial = try FeatureStoreFile(data: try builder.build(from: extract, writing: part).data)
        try partial.verify()

        let wanted = Set(try whole.cells().filter { (centre.x - 1...centre.x).contains($0.x) })
        #expect(!wanted.isEmpty)
        #expect(Set(try partial.cells()) == wanted, "the cells of the part, and nothing outside it")
        for cell in wanted {
            for band in ZoomBand.allCases {
                let a = Set(try whole.features(in: cell, band: band).map { plain($0, whole) })
                let b = Set(try partial.features(in: cell, band: band).map { plain($0, partial) })
                #expect(a == b, "cell \(cell.x)/\(cell.y), band \(band)")
            }
        }
        // A part outside the extract has no cells, and the whole extract as the part is the same as building it.
        let nowhere = BoundingBox(south: 0, west: 0, north: 1, east: 1)
        #expect(try FeatureStoreFile(data: try builder.build(from: extract, writing: nowhere).data).cellCount == 0)
        let same = try FeatureStoreFile(data: try builder.build(from: extract, writing: extract.boundingBox).data)
        #expect(try same.cells() == whole.cells())
    }
}
