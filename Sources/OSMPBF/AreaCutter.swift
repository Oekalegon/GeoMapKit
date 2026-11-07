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
        var interner = StringInterner()

        // Pass 1: nodes inside the box. Their tags go into shared arrays, interned.
        progress?(.insideNodes)
        var records: [NodeRecord] = []
        var nodeTagKeys: [UInt32] = []
        var nodeTagValues: [UInt32] = []
        try reader.forEachBlock(kinds: .nodes) { block in
            try Task.checkCancellation()
            for node in block.nodes where box.contains(node.coordinate) {
                records.append(try Self.record(
                    for: node, tagKeys: &nodeTagKeys, tagValues: &nodeTagValues, interner: &interner
                ))
            }
        }
        var inside = NodeTable(sorting: consume records)
        if let duplicate = inside.firstDuplicateID {
            throw AreaCutterError.duplicateID(kind: "node", id: duplicate)
        }

        // Pass 2: ways with a node inside, kept in columns.
        progress?(.ways)
        var keptWayIDs = Set<Int64>()
        var ways = WayAccumulator()
        try reader.forEachBlock(kinds: .ways) { block in
            try Task.checkCancellation()
            for way in block.ways where way.nodeIDs.contains(where: inside.contains) {
                guard keptWayIDs.insert(way.id).inserted else {
                    throw AreaCutterError.duplicateID(kind: "way", id: way.id)
                }
                try ways.append(way, interner: &interner)
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
                    case .way: keptWayIDs.contains(member.id)
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
        var memberNodeIDs: [Int64] = []
        for relation in selected.values {
            let wayMembers = relation.members.filter { $0.type == .way }
            if wayMembers.count <= memberLimit {
                for member in wayMembers where !keptWayIDs.contains(member.id) { wantedWayIDs.insert(member.id) }
            }
            for member in relation.members where member.type == .node { memberNodeIDs.append(member.id) }
        }

        // Pass 4: the member ways that were not already kept.
        if !wantedWayIDs.isEmpty {
            progress?(.memberWays)
            try reader.forEachBlock(kinds: .ways) { block in
                try Task.checkCancellation()
                for way in block.ways where wantedWayIDs.contains(way.id) {
                    guard keptWayIDs.insert(way.id).inserted else {
                        throw AreaCutterError.duplicateID(kind: "way", id: way.id)
                    }
                    try ways.append(way, interner: &interner)
                }
            }
        }

        // The nodes that kept ways and relations refer to, as a sorted array of IDs.
        let referenced = SortedIDs(unsorted: ways.vertices + memberNodeIDs)
        let wanted = SortedIDs(sortedUnique: referenced.ids.filter { !inside.contains($0) })

        // Pass 5: referenced nodes outside the box.
        var outside: [NodeRecord] = []
        var foundOutside = 0
        if !wanted.ids.isEmpty {
            progress?(.outsideNodes)
            let wantedSet = Set(wanted.ids)
            var found = Set<Int64>()
            try reader.forEachBlock(kinds: .nodes) { block in
                try Task.checkCancellation()
                for node in block.nodes where wantedSet.contains(node.id) {
                    guard found.insert(node.id).inserted else {
                        throw AreaCutterError.duplicateID(kind: "node", id: node.id)
                    }
                    outside.append(try Self.record(
                        for: node, tagKeys: &nodeTagKeys, tagValues: &nodeTagValues, interner: &interner
                    ))
                }
            }
            foundOutside = found.count
        }

        // Assemble the result.
        progress?(.assembly)
        // Keep the inside nodes that are tagged or referenced, compacting in place.
        var insideRecords = inside.takeRecords()
        inside = NodeTable(sorting: [])
        var kept = 0
        var cursor = 0
        for index in insideRecords.indices {
            let record = insideRecords[index]
            while cursor < referenced.ids.count && referenced.ids[cursor] < record.id { cursor += 1 }
            let isReferenced = cursor < referenced.ids.count && referenced.ids[cursor] == record.id
            if record.tagCount > 0 || isReferenced {
                insideRecords[kept] = record
                kept += 1
            }
        }
        insideRecords.removeLast(insideRecords.count - kept)
        outside.sort { $0.id < $1.id }

        // Merge the two sorted lists into node columns; the tags are copied into node order.
        var nodeIDs: [Int64] = []
        var latitudes: [Int32] = []
        var longitudes: [Int32] = []
        var nodeTags = TagColumns()
        let total = insideRecords.count + outside.count
        nodeIDs.reserveCapacity(total)
        latitudes.reserveCapacity(total)
        longitudes.reserveCapacity(total)
        var i = 0
        var j = 0
        while i < insideRecords.count || j < outside.count {
            let useInside = j >= outside.count || (i < insideRecords.count && insideRecords[i].id < outside[j].id)
            let record = useInside ? insideRecords[i] : outside[j]
            if useInside { i += 1 } else { j += 1 }
            nodeIDs.append(record.id)
            latitudes.append(record.latitude)
            longitudes.append(record.longitude)
            let range = Int(record.tagStart)..<Int(record.tagStart + record.tagCount)
            try nodeTags.append(keys: nodeTagKeys[range], values: nodeTagValues[range])
        }
        insideRecords = []
        outside = []
        nodeTagKeys = []
        nodeTagValues = []

        // Relations: members and tags in columns, with completeness computed from what is present.
        var relationIDs: [Int64] = []
        var memberOffsets: [UInt32] = [0]
        var memberTypes: [UInt8] = []
        var memberIDs: [Int64] = []
        var memberRoles: [UInt32] = []
        var complete: [Bool] = []
        var relationTags = TagColumns()
        for relation in selected.values.sorted(by: { $0.id < $1.id }) {
            relationIDs.append(relation.id)
            var isComplete = true
            for member in relation.members {
                memberTypes.append(UInt8(member.type.rawValue))
                memberIDs.append(member.id)
                memberRoles.append(try interner.intern(member.role))
                switch member.type {
                case .node: if SortedIDs.index(of: member.id, in: nodeIDs) == nil { isComplete = false }
                case .way: if !keptWayIDs.contains(member.id) { isComplete = false }
                case .relation: break
                }
            }
            memberOffsets.append(try CheckedOffset.make(memberIDs.count))
            complete.append(isComplete)
            try relationTags.append(relation.orderedTags, interner: &interner)
        }

        let strings = interner.frozen()
        return OSMExtract(
            header: header, boundingBox: box,
            nodes: ExtractedNodes(
                ids: nodeIDs, latitudes: latitudes, longitudes: longitudes,
                tagOffsets: nodeTags.offsets, tagKeys: nodeTags.keys, tagValues: nodeTags.values, strings: strings
            ),
            ways: ways.finished(strings: strings),
            relations: ExtractedRelations(
                ids: relationIDs, memberOffsets: memberOffsets, memberTypes: memberTypes, memberIDs: memberIDs,
                memberRoles: memberRoles, complete: complete, tagOffsets: relationTags.offsets,
                tagKeys: relationTags.keys, tagValues: relationTags.values, strings: strings
            ),
            strings: strings,
            missingNodeCount: wanted.ids.count - foundOutside
        )
    }

    /// A compact record for a node, with its tags interned (sorted by key) into the shared arrays.
    private static func record(
        for node: OSMNode, tagKeys: inout [UInt32], tagValues: inout [UInt32], interner: inout StringInterner
    ) throws -> NodeRecord {
        guard let latitude = scaled(node.coordinate.latitude, limit: 90),
              let longitude = scaled(node.coordinate.longitude, limit: 180) else {
            throw PBFError.malformed("node \(node.id) has an invalid coordinate")
        }
        let start = try CheckedOffset.make(tagKeys.count)
        for tag in node.orderedTags {
            tagKeys.append(try interner.intern(tag.key))
            tagValues.append(try interner.intern(tag.value))
        }
        _ = try CheckedOffset.make(tagKeys.count)
        return NodeRecord(
            id: node.id, latitude: latitude, longitude: longitude,
            tagStart: start, tagCount: UInt32(node.orderedTags.count)
        )
    }

    /// Degrees as a 32-bit integer in 1e-7 degrees (OSM's precision), or `nil` if not finite or beyond `limit`.
    private static func scaled(_ degrees: Double, limit: Double) -> Int32? {
        guard degrees.isFinite, abs(degrees) <= limit else { return nil }
        return Int32((degrees * 1e7).rounded())
    }
}
