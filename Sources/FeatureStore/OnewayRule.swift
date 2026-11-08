/// The direction of travel of a road, from its OSM tags: one rule for everything that reads roads (the map, and later the router).
public enum OnewayRule {
    /// The direction in which a road may be travelled, relative to its vertices.
    ///
    /// A roundabout is one-way along its vertices whatever else it says. Otherwise the `oneway` tag decides (`yes`, `true`, `1`
    /// along the vertices, `-1` or `reverse` against them, anything else, such as `no` or `reversible`, both ways). Without
    /// the tag a motorway and a motorway link are one-way along their vertices, as OSM defines them, and any other road is
    /// two-way.
    ///
    /// - Parameters:
    ///   - oneway: The value of the `oneway` tag, or `nil` if the way has none.
    ///   - highway: The value of the `highway` tag, or `nil`.
    ///   - junction: The value of the `junction` tag, or `nil`.
    /// - Returns: 1 for along the vertices, -1 for against them, 0 for both ways.
    public static func flow(oneway: String?, highway: String?, junction: String?) -> Int {
        if junction == "roundabout" { return 1 }
        switch oneway {
        case "yes", "true", "1": return 1
        case "-1", "reverse": return -1
        case nil: return highway == "motorway" || highway == "motorway_link" ? 1 : 0
        default: return 0
        }
    }
}
