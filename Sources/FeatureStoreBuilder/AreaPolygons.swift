import FeatureStore
import OSMPBF

/// The polygons of an extract: its closed ways and its complete multipolygon relations, with their holes.
enum AreaPolygons {
    /// Collects the polygons a caller is interested in.
    ///
    /// - Parameters:
    ///   - extract: The extract.
    ///   - classifier: The classifier that is given to `role`.
    ///   - role: Says, from the classification and the tags, whether the caller wants a polygon, and what it is for. Called for
    ///     every closed way and every complete multipolygon before anything is projected, so an object nobody wants costs little.
    /// - Returns: One entry per wanted polygon, in metres. A relation that is incomplete in the extract is not used.
    static func collect<Role>(
        extract: OSMExtract, classifier: FeatureClassifier,
        role: (Classification, any ClassifierTags) -> Role?
    ) -> [(role: Role, polygon: AreaPolygon)] {
        let projection = LocalMetres(around: extract.boundingBox)
        func polygon(from rings: [[PackedPoint]]) -> AreaPolygon? {
            AreaPolygon(rings: rings.map { $0.map { projection.project($0) } })
        }
        var found: [(role: Role, polygon: AreaPolygon)] = []
        for position in extract.ways.indices {
            let nodeIDs = extract.ways.nodeIDs(at: position)
            guard nodeIDs.count >= 4, nodeIDs.first == nodeIDs.last else { continue }
            let tags = extract.ways.tags(at: position)
            let classification = classifier.classify(tags, shape: .closedWay)
            guard let wanted = role(classification, tags) else { continue }
            let (runs, gaps) = FeatureStoreBuilder.runs(ofWayAt: position, in: extract)
            guard gaps == 0, runs.count == 1, let area = polygon(from: [runs[0]]) else { continue }
            found.append((wanted, area))
        }
        for position in extract.relations.indices {
            let item = extract.relations[position]
            let relation = item.relation
            guard item.isComplete, relation.tagValue(forKey: "type") == "multipolygon" else { continue }
            let tags = ClassifierTagArray(relation.orderedTags)
            let classification = classifier.classify(tags, shape: .multipolygon)
            guard let wanted = role(classification, tags) else { continue }
            var members: [MultipolygonMember] = []
            for member in relation.members where member.type == .way {
                let memberRole = MultipolygonRole(osmRole: member.role)
                guard memberRole != .ignored, let way = extract.ways.index(ofID: member.id) else { continue }
                let nodeIDs = Array(extract.ways.nodeIDs(at: way))
                let points = nodeIDs.compactMap {
                    extract.nodes.index(ofID: $0).map { FeatureStoreBuilder.packed(extract.nodes.coordinate(at: $0)) }
                }
                members.append(MultipolygonMember(
                    wayID: member.id, role: memberRole, nodeIDs: nodeIDs, points: points.count == nodeIDs.count ? points : nil))
            }
            let assembly = MultipolygonAssembler.assemble(members: members, relationIsComplete: item.isComplete)
            guard assembly.isComplete else { continue }
            for assembled in assembly.polygons {
                if let area = polygon(from: assembled.rings) { found.append((wanted, area)) }
            }
        }
        return found
    }
}
