import FeatureStore
import GeoCore
import OSMPBF

extension FeatureStoreBuilder {
    /// Builds the sea from the coastlines in the extract and stores it as one area feature of class `sea`.
    ///
    /// The sea covers the written cells only, and is built cell by cell for every band (``SeaBuilder``), from coastlines
    /// simplified for that band. It has the object ID 0 (it is not an OSM object). Nothing is stored if the coastlines
    /// cannot be closed.
    func storeSea(
        of extract: OSMExtract, columns: ClosedRange<Int>, rows: ClosedRange<Int>, into emitter: inout FeatureEmitter
    ) throws {
        var ways: [CoastlineJoiner.Way] = []
        var broken = false
        for position in extract.ways.indices {
            if position % 4096 == 0 { try Task.checkCancellation() }
            guard extract.ways.tags(at: position).value(forKey: "natural") == "coastline" else { continue }
            let (runs, gaps) = Self.runs(ofWayAt: position, in: extract)
            // A coastline with a node missing is cut in two, so the side the water is on cannot be followed across it.
            if gaps > 0 || runs.count != 1 { broken = true; continue }
            ways.append(CoastlineJoiner.Way(
                id: extract.ways.ids[position], nodeIDs: Array(extract.ways.nodeIDs(at: position)), points: runs[0]))
        }
        emitter.report.coastlineWays = ways.count
        // A coastline that could not be used at all must still be reported: the build has no sea, and the user should know why.
        if ways.isEmpty && broken { emitter.report.seaOpenEnds = 1 }
        guard !ways.isEmpty, let block = CellRect(columns: columns, rows: rows, zoom: Self.zoom) else { return }
        let joined = CoastlineJoiner.join(ways)
        let whole = SeaBuilder.build(rings: joined.rings, chains: joined.chains, box: block)
        emitter.report.seaOpenEnds = whole.openEnds + (broken ? 1 : 0)
        guard !broken, !whole.rings.isEmpty else { return }
        emitter.report.seaPolygons = whole.seaPolygons
        emitter.report.seaIslands = whole.islands
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
