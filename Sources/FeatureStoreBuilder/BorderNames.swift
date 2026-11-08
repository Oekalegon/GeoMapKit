import FeatureStore
import OSMPBF

/// The names of the regions on either side of the border ways.
///
/// The way of a national or a state border seldom has a name of its own: the names are on the relations of the two regions it
/// separates. This index finds, for a way, the names of the border relations (levels 2 and 4) that have it as a member, so the
/// way can be named after them, for example `Norge – Sverige`, and a map can write the names along the border.
struct BorderNames {
    private var namesByWay: [FeatureClass: [Int64: [String]]] = [:]

    init(extract: OSMExtract, classifier: FeatureClassifier) {
        for position in extract.relations.indices {
            let relation = extract.relations[position].relation
            guard relation.tagValue(forKey: "type") == "boundary", let name = relation.tagValue(forKey: "name"), !name.isEmpty
            else { continue }
            let featureClass = classifier.classify(ClassifierTagArray(relation.orderedTags), shape: .multipolygon).featureClass
            guard featureClass == .countryBorder || featureClass == .boundary else { continue }
            for member in relation.members where member.type == .way {
                namesByWay[featureClass, default: [:]][member.id, default: []].append(name)
            }
        }
    }

    /// The names of the regions a way borders joined with an en dash, in alphabetical order (the data does not say which is on
    /// which side), or `nil` for a way that is no member of a border relation.
    ///
    /// A national border (`countryBorder`) is named after the countries only: it is also part of the border of a county on each
    /// side, which a label of the national border does not want. A state border (`boundary`) is named after the states.
    ///
    /// - Parameters:
    ///   - id: The OSM ID of the way.
    ///   - featureClass: The class of the way, `countryBorder` or `boundary`.
    func name(ofWay id: Int64, as featureClass: FeatureClass) -> String? {
        guard let names = namesByWay[featureClass]?[id] else { return nil }
        return Array(Set(names)).sorted().joined(separator: " – ")
    }
}
