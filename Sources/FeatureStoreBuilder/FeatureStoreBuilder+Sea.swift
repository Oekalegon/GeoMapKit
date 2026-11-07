import FeatureStore
import OSMPBF

extension FeatureStoreBuilder {
    /// Builds the sea from the coastlines in the extract and stores it as one area feature of class `sea`.
    ///
    /// The sea polygon covers the written cells only. It is stored in every band, like any other area, and has the
    /// object ID 0 (it is not an OSM object). Nothing is stored if the coastlines cannot be closed (see ``SeaBuilder``).
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
        guard !ways.isEmpty, let box = CellRect(columns: columns, rows: rows, zoom: Self.zoom) else { return }
        let joined = CoastlineJoiner.join(ways)
        let sea = SeaBuilder.build(rings: joined.rings, chains: joined.chains, box: box)
        emitter.report.coastlineWays = ways.count
        emitter.report.seaOpenEnds = sea.openEnds + (broken ? 1 : 0)
        guard !broken, !sea.rings.isEmpty else { return }
        emitter.report.seaPolygons = sea.seaPolygons
        emitter.report.seaIslands = sea.islands
        let classification = Classification(
            featureClass: .sea, subclass: 0, kind: .area, minimumBand: .overview, showsOnWatch: true)
        try emitter.emit(FeatureSpec(
            classification: classification, objectType: .way, objectID: 0, tags: [], geometry: .rings(sea.rings)))
    }
}
