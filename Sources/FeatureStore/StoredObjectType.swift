/// The kind of OSM object a feature was built from.
public enum StoredObjectType: UInt8, Sendable {
    case node = 0
    case way = 1
    case relation = 2
}
