import FeatureStore
import Foundation
import GeoCore
import OSMPBF
import Testing

@testable import FeatureStoreBuilder

/// The whole pipeline on a real file: PBF, area cut, builder, store file, reader.
///
/// The test needs the Geofabrik Liechtenstein extract (about 3.5 MB), which is not in the repository. Set
/// `GEOMAPKIT_LIECHTENSTEIN_PBF` to its path to run it; without the variable the suite is skipped, as it is on CI.
private let pbfPath = ProcessInfo.processInfo.environment["GEOMAPKIT_LIECHTENSTEIN_PBF"]

@Suite("Liechtenstein end to end", .enabled(if: pbfPath != nil))
struct LiechtensteinEndToEndTests {
    private struct Case {
        let extract: OSMExtract
        let result: BuildResult
        let file: FeatureStoreFile
        let written: (columns: ClosedRange<Int>, rows: ClosedRange<Int>)
    }


    private func build(radiusKilometres: Double, profile: BuildProfile = .full) throws -> Case {
        let path = try #require(pbfPath)
        let box = try #require(BoundingBox.around(Coordinate(latitude: 47.14, longitude: 9.52), radiusKilometres: radiusKilometres))
        let extract = try AreaCutter().cut(try PBFReader(url: URL(fileURLWithPath: path)), to: box)
        let result = try FeatureStoreBuilder(profile: profile).build(from: extract)
        let written = try #require(FeatureStoreBuilder.writtenCells(in: extract.boundingBox))
        return Case(extract: extract, result: result, file: try FeatureStoreFile(data: result.data), written: written)
    }

    private func point(_ extract: OSMExtract, node id: Int64) throws -> PackedPoint {
        FeatureStoreBuilder.packed(extract.nodes.coordinate(at: try #require(extract.nodes.index(ofID: id))))
    }

    private func isWritten(_ point: PackedPoint, _ written: (columns: ClosedRange<Int>, rows: ClosedRange<Int>)) -> Bool {
        guard let tile = CellRect.tile(owning: point, zoom: 13) else { return false }
        return written.columns.contains(tile.x) && written.rows.contains(tile.y)
    }

    private func detailFeatures(_ file: FeatureStoreFile) throws -> [StoredObjectType: [Int64: [(cell: TileID, feature: StoredFeature)]]] {
        var result: [StoredObjectType: [Int64: [(cell: TileID, feature: StoredFeature)]]] = [:]
        for cell in try file.cells() {
            for feature in try file.features(in: cell, band: .detail) {
                result[feature.objectType, default: [:]][feature.objectID, default: []].append((cell, feature))
            }
        }
        return result
    }

    private func tagPairs(_ feature: StoredFeature, _ file: FeatureStoreFile) -> [[UInt8]] {
        feature.tags.flatMap { [Array(file.stringBytes(at: $0.key) ?? Data()), Array(file.stringBytes(at: $0.value) ?? Data())] }
    }

    @Test("The file is valid and every relation, tag and tagged node of the extract is in it, byte for byte")
    func contentIsLossless() throws {
        let built = try build(radiusKilometres: 10)
        let (extract, file) = (built.extract, built.file)
        try file.verify()
        #expect(file.attribution == FeatureStoreBuilder.attribution)
        #expect(built.result.report.cellsInArea == built.written.columns.count * built.written.rows.count)

        // Every relation: tags, members and roles.
        for item in extract.relations {
            let stored = try #require(try file.relation(withID: item.relation.id))
            #expect(stored.isIncomplete == !item.isComplete)
            let expected = item.relation.orderedTags.flatMap { [Array($0.key.utf8), Array($0.value.utf8)] }
            let actual = stored.tags.flatMap { [Array(file.stringBytes(at: $0.key) ?? Data()), Array(file.stringBytes(at: $0.value) ?? Data())] }
            #expect(actual == expected, "relation \(item.relation.id) tags")
            #expect(stored.members.map(\.id) == item.relation.members.map(\.id))
            #expect(stored.members.map { file.stringBytes(at: $0.role).map(Array.init) } == item.relation.members.map { Array($0.role.utf8) })
        }

        // Every tagged node inside the written cells is a point with exactly its tags.
        let features = try detailFeatures(file)
        var taggedInside = 0
        for position in extract.nodes.indices where extract.nodes.hasTags(at: position) {
            let id = extract.nodes.ids[position]
            let point = FeatureStoreBuilder.packed(extract.nodes.coordinate(at: position))
            guard isWritten(point, built.written) else { continue }
            taggedInside += 1
            let stored = try #require(features[.node]?[id]?.first, "node \(id)")
            #expect(stored.feature.kind == .point && stored.feature.parts[0].points == [point])
            #expect(tagPairs(stored.feature, file) == extract.nodes.tags(at: position).flatMap { [Array($0.key.utf8), Array($0.value.utf8)] })
        }
        #expect(taggedInside > 1000)
        #expect(features[.node]?.count == taggedInside)
    }

    @Test("Every way keeps its tags, its class and every vertex inside the written cells; whole ways keep their length and area")
    func waysAreLossless() throws {
        let built = try build(radiusKilometres: 10)
        let (extract, file) = (built.extract, built.file)
        let features = try detailFeatures(file)
        let classifier = FeatureClassifier()
        var checked = 0, wholeLines = 0, wholeAreas = 0
        for position in extract.ways.indices {
            let id = extract.ways.ids[position]
            guard let pieces = features[.way]?[id] else {
                // Not stored: either outside the written cells, or a member the multipolygons hold.
                continue
            }
            checked += 1
            let nodeIDs = Array(extract.ways.nodeIDs(at: position))
            let original = try nodeIDs.map { try point(extract, node: $0) }
            let first = pieces[0].feature
            let nodeIDsClosed = nodeIDs.count >= 4 && nodeIDs.first == nodeIDs.last
            let expected = classifier.classify(extract.ways.tags(at: position), shape: nodeIDsClosed ? .closedWay : .openWay)
            #expect(first.classID == expected.featureClass.rawValue && first.kind == expected.kind, "way \(id) class")
            #expect(tagPairs(first, file) == extract.ways.tags(at: position).flatMap { [Array($0.key.utf8), Array($0.value.utf8)] }, "way \(id) tags")
            // Every vertex inside the written cells is stored.
            let stored = Set(pieces.flatMap { $0.feature.parts.flatMap(\.points) })
            for vertex in original where isWritten(vertex, built.written) { #expect(stored.contains(vertex), "way \(id) lost a vertex") }
            // A way that lies wholly inside keeps its length (lines) or area (rings).
            guard original.allSatisfy({ isWritten($0, built.written) }) else { continue }
            if first.kind == .line {
                wholeLines += 1
                let sum = pieces.reduce(0) { $0 + length($1.feature.parts[0].points) }
                #expect(abs(sum - length(original)) < 0.5, "way \(id) length")
            } else {
                wholeAreas += 1
                let sum = pieces.reduce(0) { $0 + projectedArea($1.feature.parts[0].points) }
                // The two border points of a cut are rounded to 1e-7 degrees (about 1 cm), so the error of the area
                // is absolute: at most about 2 cm along the length of the cut, which is bounded by the perimeter.
                let areaMetres = projectedArea(original) * pow(Geodesy.earthRadius * cos(47.14 * .pi / 180), 2)
                let errorMetres = abs(sum - projectedArea(original)) / projectedArea(original) * areaMetres
                #expect(errorMetres <= 0.02 * length(original) + areaMetres * 1e-6, "way \(id) area")
            }
        }
        #expect(checked > 30_000 && wholeLines > 10_000 && wholeAreas > 5_000)
    }

    @Test("Multipolygons: assembled ones are areas, the incomplete ones are outlines only, and nothing is filled by guessing")
    func multipolygons() throws {
        let built = try build(radiusKilometres: 10)
        let report = built.result.report
        let features = try detailFeatures(built.file)
        #expect(report.multipolygonsAssembled + report.multipolygonsIncomplete == built.extract.relations.filter {
            $0.relation.tagValue(forKey: "type") == "multipolygon"
        }.count)
        #expect(report.multipolygonsAssembled > 200 && report.multipolygonsIncomplete >= 1)
        for (_, pieces) in features[.relation] ?? [:] {
            let incomplete = pieces[0].feature.flags.contains(.incomplete)
            #expect(pieces.allSatisfy { $0.feature.flags.contains(.incomplete) == incomplete })
            #expect(pieces.allSatisfy { incomplete ? $0.feature.kind == .line : $0.feature.kind == .area })
        }
        let outlines = (features[.relation] ?? [:]).values.filter { $0[0].feature.flags.contains(.incomplete) }
        #expect(outlines.count <= report.multipolygonsIncomplete)
        // Artificial edges lie on cell borders.
        for (_, pieces) in features[.relation] ?? [:] {
            for item in pieces where item.feature.kind == .area {
                let rect = CellRect(tile: item.cell)
                for part in item.feature.parts {
                    for run in part.artificialEdges {
                        for edge in run {
                            let (a, b) = (part.points[edge], part.points[edge + 1])
                            let onBorder = (a.longitude == b.longitude && (a.longitude == rect.west || a.longitude == rect.east))
                                || (a.latitude == b.latitude && (a.latitude == rect.south || a.latitude == rect.north))
                            #expect(onBorder)
                        }
                    }
                }
            }
        }
    }

    @Test("Assembled multipolygons keep their area: outer pieces minus hole pieces equal the polygon, for every one inside the written cells")
    func multipolygonAreas() throws {
        let built = try build(radiusKilometres: 10)
        let (extract, file) = (built.extract, built.file)
        let features = try detailFeatures(file)
        /// The signed area in projected radians squared: positive for counter-clockwise rings, negative for holes.
        func signedArea(_ ring: [PackedPoint]) -> Double {
            var sum = 0.0
            for (a, b) in zip(ring, ring.dropFirst()) {
                sum += Mercator.radians(longitude: Double(a.longitude)) * Mercator.y(latitude: Double(b.latitude))
                    - Mercator.radians(longitude: Double(b.longitude)) * Mercator.y(latitude: Double(a.latitude))
            }
            return sum / 2
        }
        var compared = 0, withHoles = 0
        for item in extract.relations where item.relation.tagValue(forKey: "type") == "multipolygon" {
            var members: [MultipolygonMember] = []
            for member in item.relation.members where member.type == .way {
                let role = MultipolygonRole(osmRole: member.role)
                guard role != .ignored else { continue }
                guard let way = extract.ways.index(ofID: member.id) else {
                    members.append(MultipolygonMember(wayID: member.id, role: role, nodeIDs: [], points: nil))
                    continue
                }
                let nodeIDs = Array(extract.ways.nodeIDs(at: way))
                let points = try nodeIDs.compactMap { extract.nodes.index(ofID: $0) == nil ? nil : try point(extract, node: $0) }
                members.append(MultipolygonMember(wayID: member.id, role: role, nodeIDs: nodeIDs, points: points.count == nodeIDs.count ? points : nil))
            }
            let assembly = MultipolygonAssembler.assemble(members: members, relationIsComplete: item.isComplete)
            guard assembly.isComplete, assembly.polygons.flatMap(\.rings).allSatisfy({ $0.allSatisfy { isWritten($0, built.written) } })
            else { continue }
            let pieces = try #require(features[.relation]?[item.relation.id], "relation \(item.relation.id)")
            let stored = pieces.reduce(0) { $0 + $1.feature.parts.reduce(0) { $0 + signedArea($1.points) } }
            let expected = assembly.polygons.reduce(0) { $0 + signedArea($1.outer) + $1.inners.reduce(0) { $0 + signedArea($1) } }
            let perimeter = assembly.polygons.flatMap(\.rings).reduce(0) { $0 + length($1) }
            let scale = pow(Geodesy.earthRadius * cos(47.14 * .pi / 180), 2)
            #expect(expected > 0)
            #expect(abs(stored - expected) * scale <= 0.02 * perimeter + expected * scale * 1e-6, "relation \(item.relation.id)")
            compared += 1
            if assembly.polygons.contains(where: { !$0.inners.isEmpty }) { withHoles += 1 }
        }
        #expect(compared > 200 && withHoles > 5)
    }

    @Test("The Watch copy is a smaller subset: only flagged classes, mid and detail bands, names only")
    func watchCopy() throws {
        let full = try build(radiusKilometres: 15)
        let watch = try build(radiusKilometres: 15, profile: .watch)
        try watch.file.verify()
        #expect(watch.file.bands == [.mid, .detail])
        #expect(watch.result.data.count < full.result.data.count * 6 / 10)
        let allowed = Set([FeatureClass.path, .track, .roadMajor, .roadMinor, .railway, .waterLine, .waterArea, .forest, .landcover, .peak, .place, .poiAnchor].map(\.rawValue))
        for cell in try watch.file.cells() {
            for band in [ZoomBand.mid, .detail] {
                for feature in try watch.file.features(in: cell, band: band) {
                    #expect(allowed.contains(feature.classID) && feature.tags.isEmpty)
                }
            }
        }
        // Classes that the Watch profile includes entirely have as many detail features as the full copy. Peaks (not
        // saddles), places (only city, town, village), anchors (not toilets, viewpoints) and waterways (not ditches
        // and drains) are in the profile in part, so they have fewer.
        let fullStats = try full.file.statistics(), watchStats = try watch.file.statistics()
        let whole = [FeatureClass.path, .track, .roadMajor, .roadMinor, .railway, .waterArea, .forest, .landcover]
        for featureClass in whole {
            #expect(watchStats.detailFeaturesByClass[featureClass.rawValue] == fullStats.detailFeaturesByClass[featureClass.rawValue], "\(featureClass)")
        }
        for featureClass in [FeatureClass.peak, .place, .poiAnchor, .waterLine] {
            #expect((watchStats.detailFeaturesByClass[featureClass.rawValue] ?? 0) <= (fullStats.detailFeaturesByClass[featureClass.rawValue] ?? 0), "\(featureClass)")
        }
    }

    @Test("The same file always gives the same bytes, and a cell reads quickly")
    func deterministicAndFast() throws {
        let a = try build(radiusKilometres: 10), b = try build(radiusKilometres: 10)
        #expect(a.result.data == b.result.data)
        let busiest = try a.file.cells().max { try a.file.features(in: $0, band: .detail).count < a.file.features(in: $1, band: .detail).count }
        let cell = try #require(busiest)
        let start = ContinuousClock.now
        for _ in 0..<10 { _ = try a.file.features(in: cell, band: .detail) }
        let elapsed = (ContinuousClock.now - start) / 10
        // Measured at about 2 ms in a release build; the bound is loose for debug builds.
        #expect(elapsed < .seconds(1))
    }
}
