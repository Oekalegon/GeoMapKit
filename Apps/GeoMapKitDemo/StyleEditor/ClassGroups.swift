import FeatureStore

/// The feature classes in groups for the list of the style editor, and their names for people.
enum ClassGroups {
    struct Group: Identifiable {
        let title: String
        let classes: [FeatureClass]
        var id: String { title }
    }

    static let groups: [Group] = [
        Group(title: "Water and coast", classes: [.sea, .coastline, .waterArea, .waterEdge, .waterLine, .riverName, .pier]),
        Group(title: "Land", classes: [.landcover, .forest, .glacier, .bareGround, .wetland, .sand, .landUse, .landuseUrban, .militaryArea, .cliff]),
        Group(title: "Roads and paths", classes: [.roadMajor, .roadMinor, .roadService, .roadArea, .path, .track, .pavement, .roadPoint]),
        Group(title: "Lines", classes: [.railway, .powerLine, .aerialway, .piste, .barrier]),
        Group(title: "Buildings and places", classes: [.building, .place, .address, .transportStop]),
        Group(title: "Borders", classes: [.boundary, .countryBorder, .parkBorder, .parkBorderSea]),
        Group(title: "Points and other", classes: [.peak, .poiAnchor, .poi, .tree, .other]),
    ]

    /// The name of a class for people: `roadMajor` is "Road major".
    static func name(of featureClass: FeatureClass) -> String {
        let raw = "\(featureClass)"
        var words = ""
        for character in raw {
            if character.isUppercase, !words.isEmpty { words.append(" ") }
            words.append(words.isEmpty ? Character(character.uppercased()) : Character(character.lowercased()))
        }
        return words
    }
}
