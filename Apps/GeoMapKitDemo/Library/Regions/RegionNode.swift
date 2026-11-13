import Regions

/// One region in the tree of the picker, with the regions below it.
struct RegionNode: Identifiable, Equatable {
    /// The identifier of the region (the Geofabrik path, such as `europe/netherlands`).
    var id: String { region.id }
    /// The region.
    let region: SourceRegion
    /// The regions directly below this one, by name.
    var children: [RegionNode]

    /// The children for `List(_:children:)`, which wants `nil` for a leaf.
    var outlineChildren: [RegionNode]? { children.isEmpty ? nil : children }

    /// The tree of an index: a region whose parent is missing from the index is a root.
    static func tree(of index: RegionIndex) -> [RegionNode] {
        let byParent = Dictionary(grouping: index.regions, by: { $0.parentID.flatMap { index.region(withID: $0) }?.id })
        func nodes(under parent: String?) -> [RegionNode] {
            (byParent[parent] ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map { RegionNode(region: $0, children: nodes(under: $0.id)) }
        }
        return nodes(under: nil)
    }

    /// The part of the tree that a search keeps: a region whose name contains the text (ignoring case and diacritics) with everything
    /// below it, and the regions above a match. An empty text keeps everything.
    func filtered(by text: String) -> RegionNode? {
        let query = text.trimmingCharacters(in: .whitespaces)
        if query.isEmpty || region.name.localizedStandardContains(query) { return self }
        let kept = children.compactMap { $0.filtered(by: query) }
        return kept.isEmpty ? nil : RegionNode(region: region, children: kept)
    }
}
