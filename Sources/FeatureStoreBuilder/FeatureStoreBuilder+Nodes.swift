import FeatureStore
import OSMPBF

extension FeatureStoreBuilder {
    /// Stores every tagged node as a point feature. Untagged nodes only exist as way vertices.
    func storeNodes(of extract: OSMExtract, into emitter: inout FeatureEmitter) throws {
        for position in extract.nodes.indices where extract.nodes.hasTags(at: position) {
            if position % 4096 == 0 { try Task.checkCancellation() }
            let tags = extract.nodes.tags(at: position)
            let point = Self.packed(extract.nodes.coordinate(at: position))
            try emitter.emit(FeatureSpec(
                classification: classifier.classify(tags, shape: .node), objectType: .node,
                objectID: extract.nodes.ids[position], tags: tags.orderedTags, geometry: .point(point)))
            emitter.report.nodesStored += 1
        }
    }
}
