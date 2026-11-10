import FeatureStore
import OSMPBF

/// Derives a feature class, subclass, geometry kind, minimum band and Watch flag from OSM tags.
///
/// The rules are an ordered table; the first match wins, so one object has one
/// primary class (``classify(_:shape:)``). A few classes can be added to it as overlays
/// (``overlays(_:primary:)``): the border of a country, a state or a protected area, and
/// a piste. The result is derived data: the builder also stores all raw tags, and
/// objects that match no rule get class `FeatureClass.other`. The table has a
/// version, ``version``, that goes into the file header; change it whenever a rule
/// changes, since files built with older rules need a rebuild.
public struct FeatureClassifier: Sendable {
    /// The version of the rule table.
    public static let version: UInt16 = 21

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
        // Of the administrative boundaries only two kinds are kept as such, because a map of towns, villages and municipalities
        // every few kilometres is of no use to a runner and hides the ones that matter: national borders (level 2, on land or in
        // the sea, but not the limit of the territorial waters or an economic zone, which no one crosses on foot; the builder takes back the agreed line
        // between two countries, which two national relations share, see `storeWays`) and the
        // level of states or counties (level 4). The rule table matches one key only, so this is checked afterwards. The other
        // levels become `other`: their tags stay in the store, and nothing draws them.
        if outcome.featureClass == .boundary, tags.value(forKey: "boundary") == "administrative" {
            switch tags.value(forKey: "admin_level") {
            case "2":
                if Self.seaLimits.contains(tags.value(forKey: "border_type") ?? "") {
                    outcome = Self.fallback
                } else {
                    outcome = ClassifierOutcome(featureClass: .countryBorder, subclass: 0, band: outcome.band, watch: false)
                }
            case "4": break
            default: outcome = Self.fallback
            }
        }
        // A sidewalk or a crossing is a footway too, but it is part of the street, not a path to run: it gets its own class.
        if outcome.featureClass == .path, tags.value(forKey: "highway") == "footway",
            let kind = tags.value(forKey: "footway"), Self.pavementKinds.contains(kind)
        {
            outcome = ClassifierOutcome(featureClass: .pavement, subclass: outcome.subclass, band: .detail, watch: false)
        }
        // A coastline is a coastline whatever else the way says: islands are often also `place=islet` or `place=island`, and
        // the rule table would take the first key it knows and leave the island without its shore line.
        if tags.value(forKey: "natural") == "coastline", shape != .node {
            outcome = ClassifierOutcome(featureClass: .coastline, subclass: 1, band: .overview, watch: false)
        }
        var subclass = outcome.subclass
        switch outcome.featureClass {
        case .track:
            subclass = Self.trackGrade(tags.value(forKey: "tracktype"))
            fallthrough
        case .path, .pavement, .roadMajor, .roadMinor, .roadService, .railway, .waterLine:
            if Self.isSet(tags.value(forKey: "bridge")) { subclass |= SubclassBits.bridge }
            if Self.isSet(tags.value(forKey: "tunnel")) { subclass |= SubclassBits.tunnel }
        default:
            break
        }
        var kind: FeatureKind
        switch shape {
        case .node: kind = .point
        case .openWay: kind = .line
        case .multipolygon: kind = .area
        case .closedWay: kind = Self.isArea(tags) ? .area : .line
        }
        // The land cover classes are surfaces: a node that carries one of their tags (a single rock, a spot marked as a wetland) has
        // nothing to draw and is not stored as one of them; it stays an unclassified point with its tags.
        if kind == .point, Self.surfaceClasses.contains(outcome.featureClass) {
            return Classification(
                featureClass: Self.fallback.featureClass, subclass: 0, kind: .point, minimumBand: Self.fallback.band,
                showsOnWatch: Self.fallback.watch)
        }
        // The shore of an island is a closed line even when the way also carries an area key such as `place`.
        if outcome.featureClass == .coastline, shape != .node { kind = .line }
        // The border of a protected area is a line to stroke, never a surface (it has no fill, and the builder splits it where it
        // goes from land into the sea).
        if outcome.featureClass == .parkBorder, shape != .node { kind = .line }
        // A road or path that is an area (a yard, a pedestrian square, a parking aisle drawn as a polygon) is not a line to
        // stroke at the width of a road: it is a surface to fill.
        if kind == .area, Self.roadClasses.contains(outcome.featureClass) {
            return Classification(
                featureClass: .roadArea, subclass: subclass, kind: .area, minimumBand: .detail, showsOnWatch: false)
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

    /// The classes that are lines of the movement network; as areas they become `roadArea`.
    private static let surfaceClasses: Set<FeatureClass> = [.landcover, .glacier, .bareGround, .wetland, .sand, .landUse]
    private static let roadClasses: Set<FeatureClass> = [.roadMajor, .roadMinor, .roadService, .path, .track, .pavement]

    /// Whether a boundary is tagged as the limit of an area of sea (`border_type` territorial, economic zone, contiguous zone).
    /// Such a way is no national border, unless it is the agreed line between two countries; the builder decides that.
    func isSeaLimit(_ tags: some ClassifierTags) -> Bool {
        Self.seaLimits.contains(tags.value(forKey: "border_type") ?? "")
    }

    /// The `border_type` values of a boundary that is the limit of an area of sea, not the border between two countries.
    private static let seaLimits: Set<String> = ["territorial", "eez", "exclusive_economic_zone", "contiguous", "contiguous_zone"]

    /// The `footway` values that mark a footway as part of a street.
    private static let pavementKinds: Set<String> = ["sidewalk", "crossing", "traffic_island", "access_aisle"]

    private static let linearNatural: Set<String> = ["coastline", "cliff", "ridge", "arete", "tree_row", "valley", "no"]
    private static let linearManMade: Set<String> = ["pipeline", "cutline", "embankment", "dyke", "no"]

    /// A group of tags that make an object something besides its primary class, and the classes they may give.
    private struct OverlayGroup {
        let keys: Set<String>
        let classes: Set<FeatureClass>
    }

    /// What an object can be as well as its primary class: the border of a country or a state, the border of a protected area and a
    /// piste. The primary class is the first of the rule table that matches, so a stream that the national border follows is a
    /// stream, a forest that is a nature reserve is a forest and a track with a nordic piste is a track, and the border, the reserve
    /// and the piste would be lost. Every other class is no overlay: a building that is a shop has nothing more to draw, and a
    /// `landuse` is one class whatever else it is.
    private static let overlayGroups: [OverlayGroup] = [
        OverlayGroup(keys: ["boundary", "admin_level", "border_type"], classes: [.countryBorder, .boundary]),
        OverlayGroup(keys: ["boundary", "leisure"], classes: [.parkBorder]),
        OverlayGroup(keys: ["piste:type"], classes: [.piste]),
    ]

    /// The classes an object has as well as its primary class, as lines (see `overlayGroups`).
    ///
    /// Each group of tags is classified on its own, with the other tags left out, so the rule table, the levels of administrative
    /// borders and the limits of the territorial waters work as they do for an object that has only those tags.
    ///
    /// - Parameters:
    ///   - tags: The tags of the object.
    ///   - primary: The class `classify` gives the object.
    /// - Returns: The overlay classifications, never of the primary class, each a line.
    public func overlays(_ tags: some ClassifierTags, primary: FeatureClass) -> [Classification] {
        var found: [Classification] = []
        for group in Self.overlayGroups {
            let own = group.keys.compactMap { key in tags.value(forKey: key).map { OSMTag(key: key, value: $0) } }
            guard !own.isEmpty else { continue }
            let result = classify(ClassifierTagArray(own), shape: .openWay)
            if group.classes.contains(result.featureClass), result.featureClass != primary,
                !found.contains(where: { $0.featureClass == result.featureClass })
            {
                found.append(result)
            }
        }
        return found
    }

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
