import FeatureStore

/// A way that is a member of a multipolygon relation, with its geometry resolved.
struct MultipolygonMember {
    let wayID: Int64
    let role: MultipolygonRole
    /// The node IDs of the way in order. Nodes are what joins ways into rings.
    let nodeIDs: [Int64]
    /// The positions of the nodes, or `nil` if the way or any of its nodes is missing from the extract.
    let points: [PackedPoint]?

    init(wayID: Int64, role: MultipolygonRole, nodeIDs: [Int64], points: [PackedPoint]?) {
        self.wayID = wayID
        self.role = role
        self.nodeIDs = nodeIDs
        self.points = points
    }
}
