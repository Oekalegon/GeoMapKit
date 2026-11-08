/// Where the name of a line is written in relation to the line.
public enum LabelPlacement: String, Sendable, Equatable, Codable {
    /// On the line, along its course: the name of a road, a path or a river.
    case onLine
    /// Beside the line, not on it, and without crossing it: the names of the regions a border separates. A name of two sides
    /// (see `SidedName` in `FeatureStore`) puts each name on the side of its region, so that on a horizontal line the one is
    /// above and the other below. Any other name goes above the line.
    case besideLine
}
