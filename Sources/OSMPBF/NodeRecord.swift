/// A node position kept compactly while a file is scanned.
///
/// Coordinates are 32-bit integers in 1e-7 degrees (OSM's own precision). The tags
/// of the node, if any, are a range in shared tag arrays.
struct NodeRecord {
    var id: Int64
    var latitude: Int32
    var longitude: Int32
    var tagStart: UInt32
    var tagCount: UInt32
}
