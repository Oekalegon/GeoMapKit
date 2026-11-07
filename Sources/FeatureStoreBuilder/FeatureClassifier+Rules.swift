import FeatureStore

extension FeatureClassifier {
    private static func make(
        _ featureClass: FeatureClass, _ band: ZoomBand, watch: Bool, _ values: [(String, UInt8)]
    ) -> [String: ClassifierOutcome] {
        var result: [String: ClassifierOutcome] = [:]
        for (value, subclass) in values {
            result[value] = ClassifierOutcome(featureClass: featureClass, subclass: subclass, band: band, watch: watch)
        }
        return result
    }

    private static func merged(_ tables: [String: ClassifierOutcome]...) -> [String: ClassifierOutcome] {
        tables.reduce(into: [:]) { $0.merge($1) { first, _ in first } }
    }

    private static func one(_ featureClass: FeatureClass, _ band: ZoomBand, watch: Bool, sub: UInt8 = 0) -> ClassifierOutcome {
        ClassifierOutcome(featureClass: featureClass, subclass: sub, band: band, watch: watch)
    }

    /// The ordered rule table. The first matching rule wins.
    static let rules: [ClassifierRule] = {
        var rules: [ClassifierRule] = []

        // Anchors first, so a hut that is also a building is a hut.
        rules.append(ClassifierRule("natural", merged(
            make(.peak, .mid, watch: true, [("peak", 1), ("volcano", 2)]),
            make(.peak, .mid, watch: false, [("saddle", 3)]))))
        rules.append(ClassifierRule("place", merged(
            make(.place, .overview, watch: true, [("city", 1), ("town", 2)]),
            make(.place, .mid, watch: true, [("village", 3)]),
            make(.place, .detail, watch: false,
                [("hamlet", 4), ("suburb", 5), ("locality", 6), ("isolated_dwelling", 7)]))))
        rules.append(ClassifierRule("amenity", merged(
            make(.poiAnchor, .detail, watch: true, [("drinking_water", 1), ("shelter", 2)]),
            make(.poiAnchor, .detail, watch: false, [("toilets", 3)]))))
        rules.append(ClassifierRule("natural", make(.poiAnchor, .detail, watch: true, [("spring", 4)])))
        rules.append(ClassifierRule("tourism", merged(
            make(.poiAnchor, .detail, watch: true, [("alpine_hut", 5), ("wilderness_hut", 6)]),
            make(.poiAnchor, .detail, watch: false, [("viewpoint", 7)]))))

        // Movement network.
        rules.append(ClassifierRule("highway", merged(
            make(.path, .mid, watch: true,
                [("path", 1), ("footway", 2), ("bridleway", 3), ("cycleway", 4), ("steps", 5), ("via_ferrata", 6)]),
            make(.track, .mid, watch: true, [("track", 0)]),
            make(.roadMajor, .overview, watch: true, [("motorway", 1), ("trunk", 2), ("primary", 3)]),
            make(.roadMajor, .mid, watch: true,
                [("secondary", 4), ("tertiary", 5), ("motorway_link", 9), ("trunk_link", 10),
                 ("primary_link", 11), ("secondary_link", 12), ("tertiary_link", 13)]),
            make(.roadMinor, .mid, watch: true, [("unclassified", 1)]),
            make(.roadMinor, .detail, watch: true,
                [("residential", 2), ("service", 3), ("living_street", 4), ("pedestrian", 5), ("road", 6)]))))
        rules.append(ClassifierRule("railway", merged(
            make(.railway, .overview, watch: true, [("rail", 1), ("light_rail", 2), ("narrow_gauge", 3), ("funicular", 4)]),
            make(.railway, .detail, watch: true, [("tram", 5)]))))

        // Water, forest, boundaries.
        rules.append(ClassifierRule("waterway", merged(
            make(.waterLine, .overview, watch: true, [("river", 1), ("canal", 2)]),
            make(.waterLine, .mid, watch: true, [("stream", 3)]),
            make(.waterLine, .detail, watch: false, [("ditch", 4), ("drain", 5)]),
            make(.waterArea, .overview, watch: true, [("riverbank", 2)]))))
        rules.append(ClassifierRule("natural", make(.waterArea, .overview, watch: true, [("water", 1)])))
        rules.append(ClassifierRule("landuse", make(.waterArea, .overview, watch: true, [("reservoir", 3), ("basin", 4)])))
        rules.append(ClassifierRule("natural", make(.forest, .overview, watch: true, [("wood", 1)])))
        rules.append(ClassifierRule("landuse", make(.forest, .overview, watch: true, [("forest", 2)])))
        rules.append(ClassifierRule("boundary", make(.boundary, .overview, watch: false,
            [("administrative", 1), ("protected_area", 2), ("national_park", 3)])))

        // Land cover and land use.
        rules.append(ClassifierRule("natural", make(.landcover, .mid, watch: true,
            [("scrub", 1), ("heath", 2), ("grassland", 3), ("fell", 4), ("bare_rock", 5), ("scree", 6), ("shingle", 7),
             ("sand", 8), ("beach", 9), ("glacier", 10), ("wetland", 11), ("mud", 12)])))
        rules.append(ClassifierRule("landuse", make(.landcover, .mid, watch: true,
            [("meadow", 20), ("grass", 21), ("farmland", 22), ("orchard", 23), ("vineyard", 24), ("allotments", 25),
             ("quarry", 26)])))
        rules.append(ClassifierRule("leisure", make(.landcover, .mid, watch: true,
            [("park", 30), ("garden", 31), ("golf_course", 32), ("pitch", 33), ("playground", 34)])))
        rules.append(ClassifierRule("landuse", make(.landuseUrban, .mid, watch: false,
            [("residential", 1), ("industrial", 2), ("commercial", 3), ("retail", 4), ("construction", 5), ("military", 6)])))

        // Buildings, then other points of interest.
        rules.append(ClassifierRule("building", any: one(.building, .detail, watch: false)))
        rules.append(ClassifierRule("building:part", any: one(.building, .detail, watch: false)))
        for (index, key) in ["amenity", "shop", "tourism", "historic", "leisure", "man_made", "emergency"].enumerated() {
            rules.append(ClassifierRule(key, any: one(.poi, .detail, watch: false, sub: UInt8(index + 1))))
        }
        return rules
    }()

    static let fallback = one(.other, .detail, watch: false)
}
