import OSMPBF

/// What ``BorderAudit`` found: how many ways of the national border relations the builder stored as a border, and the ones it did not.
public struct BorderAuditReport: Sendable, Equatable {
    /// Why a way of a national border relation is not a border, although that is no mistake.
    public enum Expected: String, Sendable, Equatable, CaseIterable {
        /// The way is tagged as the limit of an area of sea (`border_type` territorial, eez, contiguous) and belongs to the relation of one
        /// country only: the outer limit of its waters, which no one crosses on foot. (The line between two countries is a border.)
        case limitOfOneCountry
        /// The way is a coastline: the relations of a country often have the shore as members, and the shore is no border.
        case coastline
    }

    /// The ways that are no border, with no reason to be one, that have the same tags.
    public struct Group: Sendable, Equatable {
        /// The relation count and the tags that matter, as one line, for example `2 relations boundary=administrative admin_level=2`.
        public let signature: String
        /// How many ways have it.
        public var count: Int
        /// A few of them, to look up.
        public var examples: [Example]

        /// Creates a group.
        public init(signature: String, count: Int, examples: [Example]) {
            self.signature = signature
            self.count = count
            self.examples = examples
        }
    }

    /// One way to look up.
    public struct Example: Sendable, Equatable {
        /// The OSM id of the way.
        public let wayID: Int64
        /// The names of the national border relations the way belongs to.
        public let relations: [String]

        /// Creates an example.
        public init(wayID: Int64, relations: [String]) {
            self.wayID = wayID
            self.relations = relations
        }
    }

    /// The ways that are members of national border relations (`admin_level=2`) in the extract's relations.
    public var memberWays = 0
    /// The ways the builder stored as `countryBorder`.
    public var stored = 0
    /// The ways that are no border, with a reason, by reason.
    public var expected: [Expected: Int] = [:]
    /// The member ways the extract does not hold (the relation reaches beyond the cut).
    public var notInExtract = 0
    /// The member ways that are in the extract but have no node in the stored area: the cut keeps a relation's ways whole.
    public var outsideStoredArea = 0
    /// The member ways in the stored area that are no border and have no reason to be none, in groups.
    public var unexpected: [Group] = []

    /// Creates an empty report.
    public init() {}

    /// Whether every member way in the stored area is a border or has a reason not to be.
    public var isClean: Bool { unexpected.isEmpty }

    /// The number of unexpected ways.
    public var unexpectedCount: Int { unexpected.reduce(0) { $0 + $1.count } }
}
