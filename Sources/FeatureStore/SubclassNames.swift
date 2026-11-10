/// The names of the subclasses of a feature class, as the value of the OSM tag that gave the subclass (`motorway`, `farmland`, `narrow_gauge`).
///
/// The builder writes a number in the subclass byte of every feature (the rule table in `FeatureStoreBuilder`); a style selects by the
/// name. A test in `FeatureStoreBuilderTests` checks that this table is the rule table, so the two cannot drift apart. The numbers are
/// only unique within a class, and one name can have two numbers when two tags give it (`natural=grass` and `landuse=grass`).
/// This file is generated from the rule table, except `track`: the classifier stores the `tracktype` grade as the subclass of a track, so
/// `track` is a track with no grade and `grade1` to `grade5` are the graded ones (`FeatureClassifier.trackGrade`).
public enum SubclassNames {
    /// The numbers of a subclass by its name, for each class that has named subclasses.
    private static let numbers: [FeatureClass: [String: [UInt8]]] = [
        .path: ["path": [1], "footway": [2], "bridleway": [3], "cycleway": [4], "steps": [5], "via_ferrata": [6]],
        .track: ["track": [0], "grade1": [1], "grade2": [2], "grade3": [3], "grade4": [4], "grade5": [5]],
        .roadMajor: ["motorway": [1], "trunk": [2], "primary": [3], "secondary": [4], "tertiary": [5], "motorway_link": [9], "trunk_link": [10], "primary_link": [11], "secondary_link": [12], "tertiary_link": [13]],
        .roadMinor: ["unclassified": [1], "residential": [2], "living_street": [4], "pedestrian": [5], "road": [6]],
        .railway: ["rail": [1], "light_rail": [2], "narrow_gauge": [3], "funicular": [4], "tram": [5], "subway": [6], "monorail": [7]],
        .waterLine: ["river": [1], "canal": [2], "stream": [3], "ditch": [4], "drain": [5], "dam": [6], "weir": [7]],
        .waterArea: ["water": [1], "riverbank": [2], "reservoir": [3], "basin": [4]],
        .forest: ["wood": [1], "forest": [2]],
        .landcover: ["scrub": [1], "heath": [2], "grassland": [3], "fell": [4], "shrubbery": [13], "shrub": [14], "grass": [15, 21], "meadow": [20], "farmland": [22], "orchard": [23], "vineyard": [24], "allotments": [25], "village_green": [27], "recreation_ground": [28], "flowerbed": [29], "park": [30], "garden": [31], "golf_course": [32], "pitch": [33], "playground": [34], "cemetery": [35], "brownfield": [36], "greenfield": [37], "pasture": [39]],
        .landuseUrban: ["residential": [1], "industrial": [2], "commercial": [3], "retail": [4], "construction": [5], "farmyard": [7], "garages": [8], "railway": [9]],
        .peak: ["peak": [1], "volcano": [2], "saddle": [3]],
        .place: ["city": [1], "town": [2], "village": [3], "hamlet": [4], "suburb": [5], "locality": [6], "isolated_dwelling": [7], "farm": [8], "islet": [9], "neighbourhood": [10], "quarter": [11], "square": [12]],
        .poiAnchor: ["drinking_water": [1], "shelter": [2], "toilets": [3], "spring": [4], "alpine_hut": [5], "wilderness_hut": [6], "viewpoint": [7]],
        .boundary: ["administrative": [1]],
        .powerLine: ["line": [1], "minor_line": [2], "cable": [3], "tower": [4], "pole": [5], "portal": [6]],
        .piste: ["downhill": [1], "nordic": [2], "skitour": [3], "sled": [4], "hike": [5], "sleigh": [6], "snow_park": [7], "ice_skate": [8], "snowshoe": [9], "ski_jump": [10], "playground": [11], "connection": [12]],
        .aerialway: ["cable_car": [1], "gondola": [2], "chair_lift": [3], "mixed_lift": [4], "drag_lift": [5], "t-bar": [6], "j-bar": [7], "platter": [8], "rope_tow": [9], "magic_carpet": [10], "zip_line": [11], "goods": [12], "station": [20]],
        .tree: ["tree": [1], "tree_row": [2]],
        .barrier: ["fence": [1], "wall": [2], "gate": [3], "hedge": [4], "retaining_wall": [5], "bollard": [6], "cattle_grid": [7], "stile": [8], "kissing_gate": [9], "lift_gate": [10], "city_wall": [11], "guard_rail": [12]],
        .transportStop: ["stop_position": [1], "platform": [2], "station": [3, 5], "stop_area": [4], "halt": [6], "tram_stop": [7], "bus_stop": [8]],
        .roadPoint: ["crossing": [1, 15], "traffic_signals": [2], "stop": [3], "give_way": [4], "street_lamp": [5], "turning_circle": [6], "mini_roundabout": [7], "motorway_junction": [8], "milestone": [9], "passing_place": [10], "speed_camera": [11], "elevator": [12], "turning_loop": [13], "level_crossing": [14], "tram_level_crossing": [16], "tram_crossing": [17], "switch": [18], "signal": [19], "buffer_stop": [20]],
        .cliff: ["cliff": [1]],
        .coastline: ["coastline": [1]],
        .roadService: ["service": [3]],
        .parkBorder: ["protected_area": [2], "national_park": [3], "nature_reserve": [4]],
        .pier: ["pier": [1], "breakwater": [2], "groyne": [3]],
        .militaryArea: ["military": [1]],
        .glacier: ["glacier": [1]],
        .bareGround: ["bare_rock": [1], "scree": [2], "shingle": [3], "rock": [6], "bedrock": [7], "blockfield": [8], "shale": [9], "quarry": [10]],
        .wetland: ["wetland": [1], "mud": [2]],
        .sand: ["sand": [1], "beach": [2]],
        .landUse: ["dune": [1], "moor": [2], "tundra": [3], "bog": [4]],
    ]

    /// The names of the subclasses of a class, sorted by name (empty for a class without named subclasses).
    public static func names(of featureClass: FeatureClass) -> [String] {
        (numbers[featureClass] ?? [:]).keys.sorted()
    }

    /// The subclass numbers that a name has in a class (empty if the class has no such subclass).
    public static func numbers(of name: String, in featureClass: FeatureClass) -> [UInt8] {
        numbers[featureClass]?[name] ?? []
    }

    /// The name of a subclass number (the low six bits of the subclass byte, see ``SubclassBits``) in a class, or `nil` if it has none.
    public static func name(of number: UInt8, in featureClass: FeatureClass) -> String? {
        numbers[featureClass]?.first { $0.value.contains(number) }?.key
    }

    /// Every class with its names and their numbers (for a test against the rule table, and for an editor).
    public static var all: [FeatureClass: [String: [UInt8]]] { numbers }
}
