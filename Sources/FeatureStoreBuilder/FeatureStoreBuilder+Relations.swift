import FeatureStore
import OSMPBF

extension FeatureStoreBuilder {
    /// Stores every relation in the relation table and assembles multipolygons into features.
    ///
    /// - Returns: The IDs of the ways that must not be stored separately.
    func storeRelations(of extract: OSMExtract, into emitter: inout FeatureEmitter) throws -> Set<Int64> {
        var suppressed = Set<Int64>()
        for position in extract.relations.indices {
            if position % 1024 == 0 { try Task.checkCancellation() }
            let item = extract.relations[position]
            let relation = item.relation

            if emitter.profile == .full {
                try emitter.writer.add(StoredRelation(
                    id: relation.id, isIncomplete: !item.isComplete,
                    tags: relation.orderedTags.map {
                        StoredTag(key: emitter.writer.intern($0.key), value: emitter.writer.intern($0.value))
                    },
                    members: relation.members.map {
                        StoredRelationMember(
                            type: Self.storedType($0.type), id: $0.id, role: emitter.writer.intern($0.role))
                    }))
                emitter.report.relationsStored += 1
            }

            guard relation.tagValue(forKey: "type") == "multipolygon" else { continue }
            try assemble(item, extract: extract, suppressed: &suppressed, into: &emitter)
        }
        return suppressed
    }

    private func assemble(
        _ item: ExtractedRelation, extract: OSMExtract, suppressed: inout Set<Int64>, into emitter: inout FeatureEmitter
    ) throws {
        let relation = item.relation
        var members: [MultipolygonMember] = []
        var outerWays: [Int64] = []
        for member in relation.members where member.type == .way {
            let role = MultipolygonRole(osmRole: member.role)
            guard role != .ignored else { continue }
            if role == .outer { outerWays.append(member.id) }
            guard let way = extract.ways.index(ofID: member.id) else {
                members.append(MultipolygonMember(wayID: member.id, role: role, nodeIDs: [], points: nil))
                continue
            }
            // An untagged member way has no features of its own; its geometry is part of the area.
            if extract.ways.tags(at: way).isEmpty { suppressed.insert(member.id) }
            let nodeIDs = Array(extract.ways.nodeIDs(at: way))
            let points = nodeIDs.compactMap { extract.nodes.index(ofID: $0).map { Self.packed(extract.nodes.coordinate(at: $0)) } }
            members.append(MultipolygonMember(
                wayID: member.id, role: role, nodeIDs: nodeIDs, points: points.count == nodeIDs.count ? points : nil))
        }

        // Old style: the tags are on the single outer way and the relation has only `type`.
        var tags = relation.orderedTags
        if MultipolygonAssembler.adoptsOuterWayTags(relationKeys: tags.map(\.key), outerWayCount: outerWays.count),
            let wayID = outerWays.first, let way = extract.ways.index(ofID: wayID), !extract.ways.tags(at: way).isEmpty
        {
            tags += extract.ways.tags(at: way).orderedTags
            suppressed.insert(wayID)
        }

        let assembly = MultipolygonAssembler.assemble(members: members, relationIsComplete: item.isComplete)
        emitter.report.unclosedChains += assembly.report.unclosedChains
        emitter.report.degenerateRings += assembly.report.degenerateRings
        emitter.report.orphanInnerRings += assembly.report.orphanInnerRings
        emitter.report.missingMembers += assembly.report.missingMembers

        let classification = classifier.classify(ClassifierTagArray(tags), shape: .multipolygon)
        if assembly.isComplete {
            emitter.report.multipolygonsAssembled += 1
            emitter.report.polygons += assembly.polygons.count
            let rings = assembly.polygons.flatMap(\.rings)
            if classification.featureClass == .coastline {
                // A coastline is a line, not an area: the land is not a polygon to fill (the sea is built apart, see
                // `storeSea`). An island mapped as a multipolygon gets its shore line like any coastline way.
                let shore = Classification(
                    featureClass: .coastline, subclass: classification.subclass, kind: .line,
                    minimumBand: classification.minimumBand, showsOnWatch: classification.showsOnWatch)
                try emitter.emit(FeatureSpec(
                    classification: shore, objectType: .relation, objectID: relation.id, tags: tags, geometry: .lines(rings)))
                return
            }
            try emitter.emit(FeatureSpec(
                classification: classification, objectType: .relation, objectID: relation.id, tags: tags,
                geometry: .rings(rings)))
        } else {
            emitter.report.multipolygonsIncomplete += 1
            let lines = assembly.outlines.filter { $0.count >= 2 }
            guard !lines.isEmpty else { return }
            // Outline only: a line feature carrying the `incomplete` flag, never filled.
            let outline = Classification(
                featureClass: classification.featureClass, subclass: classification.subclass, kind: .line,
                minimumBand: classification.minimumBand, showsOnWatch: classification.showsOnWatch)
            try emitter.emit(FeatureSpec(
                classification: outline, objectType: .relation, objectID: relation.id, tags: tags,
                geometry: .lines(lines), extraFlags: [.incomplete]))
        }
    }

    static func storedType(_ type: OSMMemberType) -> StoredObjectType {
        switch type {
        case .node: .node
        case .way: .way
        case .relation: .relation
        }
    }
}
