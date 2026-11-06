import GeoCore

/// Cuts a bounding box out of a PBF file.
///
/// The cut keeps whole objects, as real extracts do, so that everything in it can
/// be drawn and routed without gaps at the edge:
///
/// 1. **Nodes** inside the box are recorded.
/// 2. **Ways** with at least one node inside are kept whole, including their nodes
///    outside the box.
/// 3. **Relations** with a node member inside, or a way member that was kept, are
///    selected; relations whose members include a selected relation are selected
///    too (repeatedly).
/// 4. Selected relations are **completed**: their member ways and nodes are added
///    even if they lie far outside the box. A relation with more than
///    ``Options/relationMemberLimit`` way members is not completed, so it is
///    incomplete unless all its members happened to be present already.
/// 5. The nodes that kept ways and relations refer to, and that are outside the
///    box, are fetched.
///
/// Each step is one pass over the file that decodes only the kind of object it
/// needs, so memory is proportional to the area and not to the file.
///
/// **Known limitation.** A way is selected only if one of its *nodes* lies inside
/// the box. A way with no vertex inside is missed even if its line crosses the
/// box or its polygon covers it: for example a lake or forest outline whose
/// vertices are all far away, or a long straight road with distant vertices.
/// Relations are selected from the kept ways, so such a relation can be missed
/// too. Osmium's bounding-box extract behaves the same way. See "Areas that span
/// cells or the extract" in `docs/design/architecture.md`.
///
/// A cut is blocking and can take a while on a large file. It checks for task
/// cancellation between blocks, so run it inside a `Task` to be able to cancel it.
/// It runs on the phone or the Mac, never on the Watch, which receives cut data.
public struct AreaCutter: Sendable {
    /// A stage of a cut, reported to the `progress` callback of ``cut(_:to:progress:)``
    /// when it starts. Stages 4 and 5 are skipped when there is nothing to do.
    public enum Pass: Int, CaseIterable, Sendable {
        /// Reading the nodes inside the box.
        case insideNodes
        /// Reading the ways that touch the box.
        case ways
        /// Reading the relations that touch the box.
        case relations
        /// Reading the member ways of selected relations (completion).
        case memberWays
        /// Reading the referenced nodes outside the box.
        case outsideNodes
        /// Assembling the result in memory.
        case assembly
    }

    /// Settings for a cut.
    public struct Options: Sendable {
        /// The largest number of way members for which a relation is completed.
        /// Larger relations (national park boundaries and the like) are kept but
        /// not completed. A negative value is treated as 0.
        public var relationMemberLimit: Int

        /// Creates options.
        ///
        /// - Parameter relationMemberLimit: The completion limit; default 10,000.
        public init(relationMemberLimit: Int = 10_000) {
            self.relationMemberLimit = relationMemberLimit
        }
    }

    /// The settings used by ``cut(_:to:progress:)``.
    public let options: Options

    /// Creates a cutter.
    ///
    /// - Parameter options: The settings.
    public init(options: Options = Options()) {
        self.options = options
    }

    /// Cuts an area out of a file.
    ///
    /// Untagged nodes inside the box that no way or relation uses are dropped; they
    /// carry no information.
    ///
    /// - Parameters:
    ///   - reader: The PBF file.
    ///   - box: The area. It must be valid and must not cross the antimeridian.
    ///   - progress: Called when each stage starts, on the calling thread. Use it for
    ///     progress display or to time the stages.
    /// - Returns: The extract.
    /// - Throws: ``AreaCutterError/invalidBoundingBox`` for an invalid box,
    ///   ``AreaCutterError/duplicateID(kind:id:)`` if an object ID repeats, a
    ///   ``PBFError`` if the file is malformed, or `CancellationError` if the
    ///   surrounding task was cancelled.
    public func cut(
        _ reader: PBFReader, to box: BoundingBox, progress: ((Pass) -> Void)? = nil
    ) throws -> OSMExtract {
        guard box.isValid else { throw AreaCutterError.invalidBoundingBox }
        let header = try reader.header()
        let memberLimit = max(0, options.relationMemberLimit)

        // Pass 1: nodes inside the box.
        progress?(.insideNodes)
        var records: [NodeRecord] = []
        var insideTags: [Int64: [String: String]] = [:]
        try reader.forEachBlock(kinds: .nodes) { block in
            try Task.checkCancellation()
            for node in block.nodes where box.contains(node.coordinate) {
                records.append(NodeRecord(
                    id: node.id, latitude: node.coordinate.latitude, longitude: node.coordinate.longitude
                ))
                if !node.tags.isEmpty { insideTags[node.id] = node.tags }
            }
        }
        let inside = NodeTable(sorting: records)
        records = []
        if let duplicate = inside.firstDuplicateID {
            throw AreaCutterError.duplicateID(kind: "node", id: duplicate)
        }

        // Pass 2: ways with a node inside.
        progress?(.ways)
        var keptWays: [Int64: OSMWay] = [:]
        try reader.forEachBlock(kinds: .ways) { block in
            try Task.checkCancellation()
            for way in block.ways where way.nodeIDs.contains(where: inside.contains) {
                guard keptWays.updateValue(way, forKey: way.id) == nil else {
                    throw AreaCutterError.duplicateID(kind: "way", id: way.id)
                }
            }
        }

        // Pass 3: relations that touch the area.
        progress?(.relations)
        var selected: [Int64: OSMRelation] = [:]
        var pending: [OSMRelation] = []
        try reader.forEachBlock(kinds: .relations) { block in
            try Task.checkCancellation()
            for relation in block.relations {
                let touches = relation.members.contains { member in
                    switch member.type {
                    case .node: inside.contains(member.id)
                    case .way: keptWays[member.id] != nil
                    case .relation: false
                    }
                }
                if touches {
                    guard selected.updateValue(relation, forKey: relation.id) == nil else {
                        throw AreaCutterError.duplicateID(kind: "relation", id: relation.id)
                    }
                } else if relation.members.contains(where: { $0.type == .relation }) {
                    pending.append(relation)
                }
            }
        }
        // Relations of relations: select parents of selected relations until nothing changes.
        var added = true
        while added && !pending.isEmpty {
            added = false
            var stillPending: [OSMRelation] = []
            for relation in pending {
                if relation.members.contains(where: { $0.type == .relation && selected[$0.id] != nil }) {
                    selected[relation.id] = relation
                    added = true
                } else {
                    stillPending.append(relation)
                }
            }
            pending = stillPending
        }

        // Completion: the member ways and nodes of selected relations.
        var wantedWayIDs = Set<Int64>()
        var memberNodeIDs = Set<Int64>()
        for relation in selected.values {
            let wayMembers = relation.members.filter { $0.type == .way }
            if wayMembers.count <= memberLimit {
                for member in wayMembers where keptWays[member.id] == nil { wantedWayIDs.insert(member.id) }
            }
            for member in relation.members where member.type == .node { memberNodeIDs.insert(member.id) }
        }

        // Pass 4: the member ways that were not already kept.
        if !wantedWayIDs.isEmpty {
            progress?(.memberWays)
            try reader.forEachBlock(kinds: .ways) { block in
                try Task.checkCancellation()
                for way in block.ways where wantedWayIDs.contains(way.id) {
                    guard keptWays.updateValue(way, forKey: way.id) == nil else {
                        throw AreaCutterError.duplicateID(kind: "way", id: way.id)
                    }
                }
            }
        }

        // Pass 5: referenced nodes outside the box.
        var referenced = memberNodeIDs
        for way in keptWays.values { referenced.formUnion(way.nodeIDs) }
        let wanted = referenced.filter { !inside.contains($0) }
        var outside: [OSMNode] = []
        if !wanted.isEmpty {
            progress?(.outsideNodes)
            var foundOutside = Set<Int64>()
            try reader.forEachBlock(kinds: .nodes) { block in
                try Task.checkCancellation()
                for node in block.nodes where wanted.contains(node.id) {
                    guard foundOutside.insert(node.id).inserted else {
                        throw AreaCutterError.duplicateID(kind: "node", id: node.id)
                    }
                    outside.append(node)
                }
            }
        }

        // Assemble the result.
        progress?(.assembly)
        var nodes = outside
        nodes.reserveCapacity(outside.count + inside.records.count)
        for record in inside.records {
            let tags = insideTags[record.id]
            if tags != nil || referenced.contains(record.id) {
                nodes.append(OSMNode(
                    id: record.id,
                    coordinate: Coordinate(latitude: record.latitude, longitude: record.longitude),
                    tags: tags ?? [:]
                ))
            }
        }
        nodes.sort { $0.id < $1.id }
        let nodeIDs = Set(nodes.map(\.id))

        let relations = selected.values.sorted { $0.id < $1.id }.map { relation in
            ExtractedRelation(
                relation: relation,
                isComplete: relation.members.allSatisfy { member in
                    switch member.type {
                    case .node: nodeIDs.contains(member.id)
                    case .way: keptWays[member.id] != nil
                    case .relation: true
                    }
                }
            )
        }
        return OSMExtract(
            header: header, boundingBox: box, nodes: nodes,
            ways: keptWays.values.sorted { $0.id < $1.id }, relations: relations,
            missingNodeCount: wanted.count - outside.count
        )
    }
}
