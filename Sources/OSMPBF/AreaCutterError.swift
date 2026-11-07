/// An error raised while cutting an area out of a PBF file.
public enum AreaCutterError: Error, Equatable, Sendable {
    /// The bounding box has non-finite or out-of-range edges, or its south edge is
    /// north of its north edge, or its west edge is east of its east edge.
    case invalidBoundingBox

    /// The file contains two objects of the same kind with the same ID among the
    /// objects the cut needs. OSM IDs are unique within a kind, so the file is
    /// corrupt or is a history file; the cut refuses to guess which one is right.
    case duplicateID(kind: String, id: Int64)

    /// The extract would hold more than 2^32 vertices, tags or strings, which its
    /// 32-bit offsets cannot address. Cut a smaller area.
    case extractTooLarge
}
