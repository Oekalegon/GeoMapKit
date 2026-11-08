/// An error raised while reading a region index.
public enum RegionError: Error, Equatable, Sendable {
    /// The index is not valid JSON, or is not the GeoJSON collection of regions that is expected. The text says what is wrong.
    case invalidIndex(String)

    /// Two regions in the index have the same ID.
    case duplicateRegion(String)
}
