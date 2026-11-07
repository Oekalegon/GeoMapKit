import FeatureStore

/// Derives a feature class, subclass, geometry kind, minimum band and Watch flag from OSM tags.
///
/// The rules are an ordered table; the first match wins, so one object has one
/// class. The result is derived data: the builder also stores all raw tags, and
/// objects that match no rule get class `FeatureClass.other`. The table has a
/// version, ``version``, that goes into the file header; change it whenever a rule
/// changes, since files built with older rules need a rebuild.
public struct FeatureClassifier: Sendable {
    /// The version of the rule table.
    public static let version: UInt16 = 4

    /// Creates a classifier.
    public init() {}

    /// Classifies one OSM object.
    ///
    /// - Parameters:
    ///   - tags: The tags of the object.
    ///   - shape: Whether it is a node, an open or closed way, or an assembled multipolygon.
    /// - Returns: The classification. Nodes are points, open ways are lines, assembled
    ///   multipolygons are areas, and a closed way is an area if its tags say so
    ///   (see ``isArea(_:)``) and a line otherwise.
    public func classify(_ tags: some ClassifierTags, shape: ElementShape) -> Classification {
        var outcome = firstOutcome(in: tags) ?? Self.fallback
        // A national border is an administrative boundary of level 2; the rule table matches one key only. Borders in
        // the sea (`maritime=yes`, the limit of territorial waters) stay boundaries, so no wide band is drawn on water.
        if outcome.featureClass == .boundary, tags.value(forKey: "boundary") == "administrative",
            tags.value(forKey: "admin_level") == "2", tags.value(forKey: "maritime") != "yes"
        {
            outcome = ClassifierOutcome(featureClass: .countryBorder, subclass: 0, band: outcome.band, watch: false)
        }
        // A sidewalk or a crossing is a footway too, but it is part of the street, not a path to run: it gets its own class.
        if outcome.featureClass == .path, tags.value(forKey: "highway") == "footway",
            let kind = tags.value(forKey: "footway"), Self.pavementKinds.contains(kind)
        {
            outcome = ClassifierOutcome(featureClass: .pavement, subclass: outcome.subclass, band: .detail, watch: false)
        }
        var subclass = outcome.subclass
        switch outcome.featureClass {
        case .track:
            subclass = Self.trackGrade(tags.value(forKey: "tracktype"))
            fallthrough
        case .path, .roadMajor, .roadMinor, .railway, .waterLine:
            if Self.isSet(tags.value(forKey: "bridge")) { subclass |= SubclassBits.bridge }
            if Self.isSet(tags.value(forKey: "tunnel")) { subclass |= SubclassBits.tunnel }
        default:
            break
        }
        let kind: FeatureKind
        switch shape {
        case .node: kind = .point
        case .openWay: kind = .line
        case .multipolygon: kind = .area
        case .closedWay: kind = Self.isArea(tags) ? .area : .line
        }
        return Classification(
            featureClass: outcome.featureClass, subclass: subclass, kind: kind, minimumBand: outcome.band,
            showsOnWatch: outcome.watch)
    }

    /// Whether the tags of a closed way describe an area rather than a closed line.
    ///
    /// `area=no` is always a line and `area=yes` always an area. Otherwise a way with a
    /// `highway`, `railway` or `barrier` tag is a line, and one with an area key
    /// (`building`, `landuse`, `leisure`, `amenity`, `tourism`, `shop`, `historic`, `aeroway`,
    /// `place`, most `natural` and `man_made` values, and so on) is an area.
    public static func isArea(_ tags: some ClassifierTags) -> Bool {
        switch tags.value(forKey: "area") {
        case "no": return false
        case "yes": return true
        default: break
        }
        for key in ["highway", "railway", "barrier"] where isSet(tags.value(forKey: key)) { return false }
        for key in ["building", "building:part", "landuse", "leisure", "amenity", "tourism", "shop", "historic", "aeroway", "place"]
        where isSet(tags.value(forKey: key)) { return true }
        if let natural = tags.value(forKey: "natural"), !natural.isEmpty, !linearNatural.contains(natural) { return true }
        if let manMade = tags.value(forKey: "man_made"), !manMade.isEmpty, !linearManMade.contains(manMade) { return true }
        if tags.value(forKey: "waterway") == "riverbank" { return true }
        if let boundary = tags.value(forKey: "boundary"), boundary == "protected_area" || boundary == "national_park" { return true }
        return false
    }

    /// The `footway` values that mark a footway as part of a street.
    private static let pavementKinds: Set<String> = ["sidewalk", "crossing", "traffic_island", "access_aisle"]

    private static let linearNatural: Set<String> = ["coastline", "cliff", "ridge", "arete", "tree_row", "valley", "no"]
    private static let linearManMade: Set<String> = ["pipeline", "cutline", "embankment", "dyke", "no"]

    private func firstOutcome(in tags: some ClassifierTags) -> ClassifierOutcome? {
        for rule in Self.rules {
            if let value = tags.value(forKey: rule.key), let outcome = rule.match(value) { return outcome }
        }
        return nil
    }

    private static func isSet(_ value: String?) -> Bool {
        guard let value, !value.isEmpty else { return false }
        return value != "no"
    }

    private static func trackGrade(_ value: String?) -> UInt8 {
        switch value {
        case "grade1": 1
        case "grade2": 2
        case "grade3": 3
        case "grade4": 4
        case "grade5": 5
        default: 0
        }
    }
}
