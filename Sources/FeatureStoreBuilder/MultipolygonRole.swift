/// The role of a way in a multipolygon relation.
enum MultipolygonRole: Equatable {
    case outer
    case inner
    /// Any other role (for example `outline`); such members do not take part in the assembly.
    case ignored

    /// Maps an OSM member role. An empty role counts as `outer`, as older data has it.
    init(osmRole: String) {
        switch osmRole {
        case "outer", "": self = .outer
        case "inner": self = .inner
        default: self = .ignored
        }
    }
}
