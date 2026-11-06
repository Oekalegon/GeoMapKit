/// A set of OSM object kinds, used to skip decoding the kinds a pass does not need.
public struct OSMObjectKinds: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Nodes (plain and dense).
    public static let nodes = OSMObjectKinds(rawValue: 1 << 0)

    /// Ways.
    public static let ways = OSMObjectKinds(rawValue: 1 << 1)

    /// Relations.
    public static let relations = OSMObjectKinds(rawValue: 1 << 2)

    /// All kinds.
    public static let all: OSMObjectKinds = [.nodes, .ways, .relations]
}
