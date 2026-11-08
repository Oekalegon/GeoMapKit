import FeatureStore
import GeoCore
import OSMPBF

extension FeatureStoreBuilder {
    /// Joins the coastlines in the extract and builds the sea of the whole stored area.
    ///
    /// This comes before the ways are stored, because the ways need to know where the sea is (the border of a protected area is
    /// another colour in it). Nothing is built if the coastlines cannot be closed.
    func prepareSea(
        of extract: OSMExtract, columns: ClosedRange<Int>, rows: ClosedRange<Int>, into emitter: inout FeatureEmitter
    ) throws -> PreparedSea? {
        var ways: [CoastlineJoiner.Way] = []
        var skipped = 0
        for position in extract.ways.indices {
            if position % 4096 == 0 { try Task.checkCancellation() }
            guard extract.ways.tags(at: position).value(forKey: "natural") == "coastline" else { continue }
            let (runs, gaps) = Self.runs(ofWayAt: position, in: extract)
            // A coastline with a node missing is cut in two; the way is left out and the gap it leaves is closed below, if it can be.
            if gaps > 0 || runs.count != 1 { skipped += 1; continue }
            ways.append(CoastlineJoiner.Way(
                id: extract.ways.ids[position], nodeIDs: Array(extract.ways.nodeIDs(at: position)), points: runs[0]))
        }
        emitter.report.coastlineWays = ways.count
        emitter.report.coastlineWaysSkipped = skipped
        // A coastline that could not be used at all must still be reported: the build has no sea, and the user should know why.
        if ways.isEmpty && skipped > 0 { emitter.report.seaOpenEnds = 1 }
        guard !ways.isEmpty, let block = CellRect(columns: columns, rows: rows, zoom: Self.zoom) else { return nil }
        let joinedWays = CoastlineJoiner.join(ways)
        // Coastlines that end inside the area (the extract stops at a country border) are joined with straight lines.
        var borders: [[PackedPoint]] = []
        for position in extract.ways.indices {
            let tags = extract.ways.tags(at: position)
            guard tags.value(forKey: "boundary") == "administrative", tags.value(forKey: "admin_level") == "2" else { continue }
            borders.append(contentsOf: Self.runs(ofWayAt: position, in: extract).runs)
        }
        let closing = CoastlineGaps.close(chains: joinedWays.chains, rings: joinedWays.rings, block: block, borders: borders)
        let joined = CoastlineJoiner.Result(rings: closing.rings, chains: closing.chains)
        emitter.report.seaGapsClosed = closing.gaps.count
        emitter.report.seaEndsExtended = closing.extended
        emitter.report.seaLongestGap = closing.gaps.max() ?? 0
        let whole = SeaBuilder.build(rings: joined.rings, chains: joined.chains, box: block)
        emitter.report.seaOpenEnds = whole.openEnds
        guard !whole.rings.isEmpty else { return nil }
        emitter.report.seaPolygons = whole.seaPolygons
        emitter.report.seaIslands = whole.islands
        return PreparedSea(joined: joined, whole: whole, block: block)
    }

    /// Stores the sea as one area feature of class `sea`.
    ///
    /// The sea covers the written cells only, and is built cell by cell for every band (``SeaBuilder``), from coastlines
    /// simplified for that band. It has the object ID 0 (it is not an OSM object).
    func storeSea(
        _ prepared: PreparedSea, columns: ClosedRange<Int>, rows: ClosedRange<Int>, into emitter: inout FeatureEmitter
    ) throws {
        let joined = prepared.joined, whole = prepared.whole, block = prepared.block
        emitter.report.featuresByClass[.sea] = 1

        for band in ZoomBand.allCases {
            if profile == .watch && band == .overview { continue }
            try Task.checkCancellation()
            let tolerance = GeometrySimplifier.tolerance(for: band)
            let chains = joined.chains.map { chain in tolerance.map { GeometrySimplifier.simplify(line: chain, tolerance: $0) } ?? chain }
            let rings = joined.rings.compactMap { ring in tolerance.map { GeometrySimplifier.simplify(ring: ring, tolerance: $0) } ?? ring }
            let lines = SeaBuilder.Lines(rings: rings, chains: chains)
            let sea = tolerance == nil ? whole.rings : SeaBuilder.build(lines: lines, box: block).rings
            let blockParts = SeaBuilder.parts(lines: lines, sea: sea, columns: columns, rows: rows, zoom: Self.zoom)
            for row in rows {
                for column in columns {
                    guard let found = blockParts[(row - rows.lowerBound) * columns.count + (column - columns.lowerBound)], !found.isEmpty,
                        let cell = TileID(zoom: Self.zoom, x: column, y: row)
                    else { continue }
                    try emitter.writer.add(
                        StoredFeature(
                            classID: FeatureClass.sea.rawValue, subclass: 0, kind: .area, objectType: .way, objectID: 0,
                            flags: [], offsetAlongLine: 0, nameID: nil, tags: [], parts: found),
                        band: band, cell: cell)
                }
            }
        }
    }
}
