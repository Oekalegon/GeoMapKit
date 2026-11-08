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
                [("hamlet", 4), ("suburb", 5), ("locality", 6), ("isolated_dwelling", 7), ("farm", 8), ("islet", 9),
                 ("neighbourhood", 10), ("quarter", 11), ("square", 12)]))))
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
            // Every street belongs in the mid band, with the paths and tracks: a runner can run them as well as the paths, and
            // a map at zoom 14 without them is a map of the main roads and the paths only. Service roads are a class of their
            // own so that the style can draw them finer than the streets.
            make(.roadMinor, .mid, watch: true, [("residential", 2), ("living_street", 4), ("pedestrian", 5), ("road", 6)]),
            make(.roadService, .mid, watch: true, [("service", 3)]))))
        rules.append(ClassifierRule("railway", merged(
            make(.railway, .overview, watch: true, [("rail", 1), ("light_rail", 2), ("narrow_gauge", 3), ("funicular", 4)]),
            make(.railway, .detail, watch: true, [("tram", 5)]),
            make(.railway, .detail, watch: false, [("subway", 6), ("monorail", 7)]))))

        // Landmarks that a runner navigates by (rule table version 2).
        rules.append(ClassifierRule("power", merged(
            make(.powerLine, .mid, watch: true, [("line", 1), ("minor_line", 2), ("cable", 3)]),
            make(.powerLine, .detail, watch: true, [("tower", 4)]),
            make(.powerLine, .detail, watch: false, [("pole", 5), ("portal", 6)]))))
        rules.append(ClassifierRule("aerialway", merged(
            make(.aerialway, .mid, watch: true,
                [("cable_car", 1), ("gondola", 2), ("chair_lift", 3), ("mixed_lift", 4), ("drag_lift", 5), ("t-bar", 6),
                 ("j-bar", 7), ("platter", 8), ("rope_tow", 9), ("magic_carpet", 10), ("zip_line", 11), ("goods", 12)]),
            make(.aerialway, .detail, watch: true, [("station", 20)]))))
        // After `highway`, so a ski trail that is also a hiking path stays a path.
        rules.append(ClassifierRule("piste:type", make(.piste, .mid, watch: true,
            [("downhill", 1), ("nordic", 2), ("skitour", 3), ("sled", 4), ("hike", 5), ("sleigh", 6), ("snow_park", 7),
             ("ice_skate", 8), ("snowshoe", 9), ("ski_jump", 10), ("playground", 11), ("connection", 12)])))
        rules.append(ClassifierRule("piste:type", any: one(.piste, .mid, watch: true)))

        // Water, forest, boundaries.
        rules.append(ClassifierRule("waterway", merged(
            make(.waterLine, .overview, watch: true, [("river", 1), ("canal", 2)]),
            make(.waterLine, .mid, watch: true, [("stream", 3)]),
            make(.waterLine, .detail, watch: false, [("ditch", 4), ("drain", 5), ("dam", 6), ("weir", 7)]),
            make(.waterArea, .overview, watch: true, [("riverbank", 2)]))))
        rules.append(ClassifierRule("natural", make(.waterArea, .overview, watch: true, [("water", 1)])))
        rules.append(ClassifierRule("landuse", make(.waterArea, .overview, watch: true, [("reservoir", 3), ("basin", 4)])))
        rules.append(ClassifierRule("natural", make(.forest, .overview, watch: true, [("wood", 1)])))
        rules.append(ClassifierRule("landuse", make(.forest, .overview, watch: true, [("forest", 2)])))
        rules.append(ClassifierRule("natural", make(.tree, .detail, watch: false, [("tree", 1), ("tree_row", 2)])))
        // Protected areas are a class of their own (rule table version 13), so that the style can draw them in green, and in blue
        // where they lie in the sea; the national and state borders stay `boundary` and `countryBorder`.
        rules.append(ClassifierRule("boundary", merged(
            make(.boundary, .overview, watch: false, [("administrative", 1)]),
            make(.parkBorder, .overview, watch: false, [("protected_area", 2), ("national_park", 3)]))))
        rules.append(ClassifierRule("leisure", make(.parkBorder, .overview, watch: false, [("nature_reserve", 4)])))

        // Land cover and land use.
        // The large kinds of land cover are in the overview band, so that at zoom 11 a village (urban land use) differs from the
        // fields, heath and bare rock around it; the small ones (lawns, allotments, flower beds) start at the mid band.
        rules.append(ClassifierRule("natural", make(.landcover, .overview, watch: true,
            [("scrub", 1), ("shrubbery", 13), ("shrub", 14), ("heath", 2), ("grassland", 3), ("fell", 4), ("bare_rock", 5), ("scree", 6), ("shingle", 7),
             ("sand", 8), ("beach", 9), ("glacier", 10), ("wetland", 11), ("mud", 12)])))
        rules.append(ClassifierRule("landuse", merged(
            make(.landcover, .overview, watch: true, [("meadow", 20), ("farmland", 22), ("orchard", 23), ("vineyard", 24), ("quarry", 26)]),
            make(.landcover, .mid, watch: true,
                [("grass", 21), ("allotments", 25), ("village_green", 27), ("recreation_ground", 28), ("flowerbed", 29)]))))
        rules.append(ClassifierRule("leisure", make(.landcover, .mid, watch: true,
            [("park", 30), ("garden", 31), ("golf_course", 32), ("pitch", 33), ("playground", 34)])))
        rules.append(ClassifierRule("landuse", make(.landuseUrban, .overview, watch: false,
            [("residential", 1), ("industrial", 2), ("commercial", 3), ("retail", 4), ("construction", 5), ("military", 6),
             ("farmyard", 7), ("garages", 8), ("railway", 9)])))
        rules.append(ClassifierRule("natural", make(.cliff, .mid, watch: false, [("cliff", 1)])))
        rules.append(ClassifierRule("natural", make(.coastline, .overview, watch: false, [("coastline", 1)])))

        // Buildings, then barriers, stops and road details, then other points of interest.
        rules.append(ClassifierRule("building", any: one(.building, .mid, watch: false)))
        rules.append(ClassifierRule("building:part", any: one(.building, .detail, watch: false)))
        rules.append(ClassifierRule("barrier", make(.barrier, .detail, watch: false,
            [("fence", 1), ("wall", 2), ("gate", 3), ("hedge", 4), ("retaining_wall", 5), ("bollard", 6), ("cattle_grid", 7),
             ("stile", 8), ("kissing_gate", 9), ("lift_gate", 10), ("city_wall", 11), ("guard_rail", 12)])))
        rules.append(ClassifierRule("barrier", any: one(.barrier, .detail, watch: false)))
        rules.append(ClassifierRule("public_transport", make(.transportStop, .detail, watch: false,
            [("stop_position", 1), ("platform", 2), ("station", 3), ("stop_area", 4)])))
        rules.append(ClassifierRule("public_transport", any: one(.transportStop, .detail, watch: false)))
        rules.append(ClassifierRule("highway", make(.transportStop, .detail, watch: false, [("bus_stop", 8)])))
        rules.append(ClassifierRule("railway", make(.transportStop, .detail, watch: false,
            [("station", 5), ("halt", 6), ("tram_stop", 7)])))
        rules.append(ClassifierRule("highway", make(.roadPoint, .detail, watch: false,
            [("crossing", 1), ("traffic_signals", 2), ("stop", 3), ("give_way", 4), ("street_lamp", 5), ("turning_circle", 6),
             ("mini_roundabout", 7), ("motorway_junction", 8), ("milestone", 9), ("passing_place", 10), ("speed_camera", 11),
             ("elevator", 12), ("turning_loop", 13)])))
        // Rail and road details at a point (rule table version 4).
        rules.append(ClassifierRule("railway", make(.roadPoint, .detail, watch: false,
            [("level_crossing", 14), ("crossing", 15), ("tram_level_crossing", 16), ("tram_crossing", 17), ("switch", 18),
             ("signal", 19), ("buffer_stop", 20)])))
        rules.append(ClassifierRule("traffic_calming", any: one(.roadPoint, .detail, watch: false, sub: 21)))
        // Piers and the like: a runner on a quay sees them, and a marina without them is a patch of empty water.
        rules.append(ClassifierRule("man_made", make(.pier, .mid, watch: false, [("pier", 1), ("breakwater", 2), ("groyne", 3)])))
        for (index, key) in ["amenity", "shop", "tourism", "historic", "leisure", "man_made", "emergency"].enumerated() {
            rules.append(ClassifierRule(key, any: one(.poi, .detail, watch: false, sub: UInt8(index + 1))))
        }
        // Objects with nothing but an address (rule table version 4): the largest group in a town.
        for key in ["addr:housenumber", "addr:housename", "addr:street", "addr:postcode", "addr:city"] {
            rules.append(ClassifierRule(key, any: one(.address, .detail, watch: false)))
        }
        return rules
    }()

    static let fallback = one(.other, .detail, watch: false)
}
