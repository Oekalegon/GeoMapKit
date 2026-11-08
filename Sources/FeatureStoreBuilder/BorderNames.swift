import FeatureStore
import OSMPBF

/// The names of the regions on either side of the border ways.
///
/// The way of a national or a state border seldom has a name of its own: the names are on the relations of the two regions it
/// separates. This index finds, for a way, the names of the border relations (levels 2 and 4) that have it as a member, so the
/// way can be named after them, and a map can write each name on the side of its region along the border.
struct BorderNames {
    /// A relation that has a way as a member.
    private struct Claim {
        var name: String
        /// Whether the region lies on the right of the way in its stored direction, `nil` if that is not known.
        var onRight: Bool?
    }

    private var claimsByWay: [FeatureClass: [Int64: [Claim]]] = [:]

    init(extract: OSMExtract, classifier: FeatureClassifier) {
        for position in extract.relations.indices {
            let relation = extract.relations[position].relation
            guard relation.tagValue(forKey: "type") == "boundary", let name = relation.tagValue(forKey: "name"), !name.isEmpty
            else { continue }
            let featureClass = classifier.classify(ClassifierTagArray(relation.orderedTags), shape: .multipolygon).featureClass
            guard featureClass == .countryBorder || featureClass == .boundary else { continue }
            let sides = BoundarySides.regionIsOnRight(of: relation, in: extract)
            for member in relation.members where member.type == .way {
                claimsByWay[featureClass, default: [:]][member.id, default: []].append(
                    Claim(name: name, onRight: sides[member.id]))
            }
        }
    }

    /// How many national border relations (level 2) have the way as a member. A way that two countries share is a border
    /// between them; the limit of the territorial waters of one country belongs to its relation alone.
    func countryRelationCount(ofWay id: Int64) -> Int {
        claimsByWay[.countryBorder]?[id]?.count ?? 0
    }

    /// The name of a border way: the regions it separates, each on its side.
    ///
    /// The result is a ``SidedName`` in text form: the names of the regions on the left of the way, looking along its stored
    /// direction, then those on the right. A side can be empty, when the region on the other side is not in the data. A region
    /// whose side is not known (see ``BoundarySides``) takes the side that is free, when the other region's side is known;
    /// when neither is known, the names are written together, alphabetically, joined with an en dash (the data does not say
    /// which is on which side), and the text is no sided name.
    ///
    /// A national border (`countryBorder`) is named after the countries only: it is also part of the border of a county on each
    /// side, which a label of the national border does not want. A state border (`boundary`) is named after the states.
    ///
    /// - Parameters:
    ///   - id: The OSM ID of the way.
    ///   - featureClass: The class of the way, `countryBorder` or `boundary`.
    /// - Returns: The name, or `nil` for a way that is no member of a border relation.
    func name(ofWay id: Int64, as featureClass: FeatureClass) -> String? {
        guard let claims = claimsByWay[featureClass]?[id], !claims.isEmpty else { return nil }
        var left = Set<String>(), right = Set<String>(), unknown = Set<String>()
        for claim in claims {
            switch claim.onRight {
            case true?: right.insert(claim.name)
            case false?: left.insert(claim.name)
            case nil: unknown.insert(claim.name)
            }
        }
        unknown.subtract(left)
        unknown.subtract(right)
        if left.isEmpty, right.isEmpty { return unknown.sorted().joined(separator: " – ") }
        // The other region is on the other side. If both sides are taken, a region of unknown side has no place.
        if left.isEmpty { left = unknown } else if right.isEmpty { right = unknown }
        return SidedName(left: left.sorted().joined(separator: " / "), right: right.sorted().joined(separator: " / ")).text
    }
}
