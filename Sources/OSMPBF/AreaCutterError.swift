/// An error raised while cutting an area out of a PBF file.
public enum AreaCutterError: Error, Equatable, Sendable {
    /// The bounding box has non-finite or out-of-range edges, or its south edge is
    /// north of its north edge, or its west edge is east of its east edge.
    case invalidBoundingBox
}
