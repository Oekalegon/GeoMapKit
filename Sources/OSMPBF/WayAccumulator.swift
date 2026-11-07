/// Collects ways in columns while a file is scanned.
struct WayAccumulator {
    var ids: [Int64] = []
    var vertexOffsets: [UInt32] = [0]
    var vertices: [Int64] = []
    var tags = TagColumns()

    mutating func append(_ way: OSMWay, interner: inout StringInterner) throws {
        ids.append(way.id)
        vertices.append(contentsOf: way.nodeIDs)
        vertexOffsets.append(try CheckedOffset.make(vertices.count))
        try tags.append(way.orderedTags, interner: &interner)
    }

    /// The finished columns, sorted by way ID.
    func finished(strings: InternedStrings) -> ExtractedWays {
        let sortedAlready = zip(ids, ids.dropFirst()).allSatisfy { $0 < $1 }
        if sortedAlready {
            return ExtractedWays(
                ids: ids, vertexOffsets: vertexOffsets, vertices: vertices,
                tagOffsets: tags.offsets, tagKeys: tags.keys, tagValues: tags.values, strings: strings
            )
        }
        let order = ids.indices.sorted { ids[$0] < ids[$1] }
        var sortedVertices: [Int64] = []
        sortedVertices.reserveCapacity(vertices.count)
        var sortedOffsets: [UInt32] = [0]
        var sortedTags = TagColumns()
        for index in order {
            sortedVertices.append(contentsOf: vertices[Int(vertexOffsets[index])..<Int(vertexOffsets[index + 1])])
            sortedOffsets.append(UInt32(sortedVertices.count))
            let range = Int(tags.offsets[index])..<Int(tags.offsets[index + 1])
            sortedTags.keys.append(contentsOf: tags.keys[range])
            sortedTags.values.append(contentsOf: tags.values[range])
            sortedTags.offsets.append(UInt32(sortedTags.keys.count))
        }
        return ExtractedWays(
            ids: order.map { ids[$0] }, vertexOffsets: sortedOffsets, vertices: sortedVertices,
            tagOffsets: sortedTags.offsets, tagKeys: sortedTags.keys, tagValues: sortedTags.values, strings: strings
        )
    }
}
