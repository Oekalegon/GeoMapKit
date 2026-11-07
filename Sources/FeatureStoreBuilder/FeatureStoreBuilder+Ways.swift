import FeatureStore
import OSMPBF

extension FeatureStoreBuilder {
    /// Stores every way as a line or area feature, except those a multipolygon already holds.
    func storeWays(of extract: OSMExtract, suppressed: Set<Int64>, into emitter: inout FeatureEmitter) throws {
        for position in extract.ways.indices {
            if position % 4096 == 0 { try Task.checkCancellation() }
            let id = extract.ways.ids[position]
            if suppressed.contains(id) {
                emitter.report.waysSuppressed += 1
                continue
            }
            let (runs, gaps) = Self.runs(ofWayAt: position, in: extract)
            if gaps > 0 { emitter.report.waysWithMissingNodes += 1 }
            guard !runs.isEmpty else {
                emitter.report.waysWithoutGeometry += 1
                continue
            }
            let nodeIDs = extract.ways.nodeIDs(at: position)
            let isClosed = gaps == 0 && nodeIDs.count >= 4 && nodeIDs.first == nodeIDs.last
            let tags = extract.ways.tags(at: position)
            let classification = classifier.classify(tags, shape: isClosed ? .closedWay : .openWay)
            let geometry: FeatureSpec.Geometry = classification.kind == .area ? .rings([runs[0]]) : .lines(runs)
            try emitter.emit(FeatureSpec(
                classification: classification, objectType: .way, objectID: id, tags: tags.orderedTags, geometry: geometry))
            emitter.report.waysStored += 1
        }
    }
}
