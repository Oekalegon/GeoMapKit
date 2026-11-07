import FeatureStore

/// One outer ring with the inner rings (holes) inside it.
struct AssembledPolygon: Equatable {
    /// The outer ring, closed, counter-clockwise in Web Mercator.
    var outer: [PackedPoint]
    /// The holes, each closed and clockwise.
    var inners: [[PackedPoint]]

    /// All rings, outer first. These are the parts of an area feature; fill with the even-odd rule.
    var rings: [[PackedPoint]] { [outer] + inners }
}
