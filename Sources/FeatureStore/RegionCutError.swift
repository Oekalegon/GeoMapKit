/// Why a region could not be cut out of a map.
public enum RegionCutError: Error, Equatable, Sendable {
    /// The area is not a box on the map: a value is not a number, or the south is above the north or the west is east of the east.
    /// An area over the antimeridian is not supported.
    case invalidArea
    /// The area covers more cells than the cutter may cut; the Watch has little room, so a small area is cut at a time.
    case tooLarge(cells: Int, limit: Int)
    /// The map has no feature of the profile in the area.
    case emptyArea
    /// The source is not a well-formed store, or its files do not agree (for example two files with different class tables).
    case store(FeatureStoreError)
    /// A file could not be read or written (the text says what the system reported), or a set of blocks was refused.
    case io(String)
}
