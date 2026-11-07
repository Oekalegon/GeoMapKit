import FeatureStore

/// The result of assembling a multipolygon relation.
struct MultipolygonAssembly: Equatable {
    /// True if every ring closed and nothing was missing. Only then are ``polygons`` filled in.
    var isComplete: Bool
    /// The polygons, in the order of the lowest way ID of their outer ring. Empty if the relation is incomplete.
    var polygons: [AssembledPolygon]
    /// For an incomplete relation, every ring and chain of ways as an open or closed line, to draw as an outline
    /// and never to fill. Empty if the relation is complete.
    var outlines: [[PackedPoint]]
    var report: AssemblyReport
}
