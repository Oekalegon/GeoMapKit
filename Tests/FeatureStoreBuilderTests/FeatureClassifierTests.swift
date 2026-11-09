import FeatureStore
import Testing

@testable import FeatureStoreBuilder

@Suite("Feature classifier")
struct FeatureClassifierTests {
    private let classifier = FeatureClassifier()

    private func classify(_ tags: [String: String], _ shape: ElementShape = .openWay) -> Classification {
        classifier.classify(tags, shape: shape)
    }

    struct Case: CustomTestStringConvertible, Sendable {
        let tags: [String: String]
        let featureClass: FeatureClass
        let band: ZoomBand
        let watch: Bool
        var testDescription: String { "\(tags) -> \(featureClass)" }
    }

    // One row per rule of the approved table.
    static let table: [Case] = [
        Case(tags: ["natural": "peak"], featureClass: .peak, band: .mid, watch: true),
        Case(tags: ["natural": "volcano"], featureClass: .peak, band: .mid, watch: true),
        Case(tags: ["natural": "saddle"], featureClass: .peak, band: .mid, watch: false),
        Case(tags: ["place": "city"], featureClass: .place, band: .overview, watch: true),
        Case(tags: ["place": "town"], featureClass: .place, band: .overview, watch: true),
        Case(tags: ["place": "village"], featureClass: .place, band: .mid, watch: true),
        Case(tags: ["place": "hamlet"], featureClass: .place, band: .detail, watch: false),
        Case(tags: ["place": "isolated_dwelling"], featureClass: .place, band: .detail, watch: false),
        Case(tags: ["amenity": "drinking_water"], featureClass: .poiAnchor, band: .detail, watch: true),
        Case(tags: ["amenity": "shelter"], featureClass: .poiAnchor, band: .detail, watch: true),
        Case(tags: ["amenity": "toilets"], featureClass: .poiAnchor, band: .detail, watch: false),
        Case(tags: ["natural": "spring"], featureClass: .poiAnchor, band: .detail, watch: true),
        Case(tags: ["tourism": "alpine_hut"], featureClass: .poiAnchor, band: .detail, watch: true),
        Case(tags: ["tourism": "wilderness_hut"], featureClass: .poiAnchor, band: .detail, watch: true),
        Case(tags: ["tourism": "viewpoint"], featureClass: .poiAnchor, band: .detail, watch: false),
        Case(tags: ["highway": "path"], featureClass: .path, band: .mid, watch: true),
        Case(tags: ["highway": "cycleway"], featureClass: .path, band: .mid, watch: true),
        Case(tags: ["highway": "via_ferrata"], featureClass: .path, band: .mid, watch: true),
        Case(tags: ["highway": "track"], featureClass: .track, band: .mid, watch: true),
        Case(tags: ["highway": "motorway"], featureClass: .roadMajor, band: .overview, watch: true),
        Case(tags: ["highway": "primary"], featureClass: .roadMajor, band: .overview, watch: true),
        Case(tags: ["highway": "secondary"], featureClass: .roadMajor, band: .mid, watch: true),
        Case(tags: ["highway": "tertiary"], featureClass: .roadMajor, band: .mid, watch: true),
        Case(tags: ["highway": "tertiary_link"], featureClass: .roadMajor, band: .mid, watch: true),
        Case(tags: ["highway": "unclassified"], featureClass: .roadMinor, band: .mid, watch: true),
        Case(tags: ["highway": "residential"], featureClass: .roadMinor, band: .mid, watch: true),
        Case(tags: ["highway": "living_street"], featureClass: .roadMinor, band: .mid, watch: true),
        Case(tags: ["highway": "service"], featureClass: .roadService, band: .mid, watch: true),
        Case(tags: ["highway": "pedestrian"], featureClass: .roadMinor, band: .mid, watch: true),
        Case(tags: ["railway": "rail"], featureClass: .railway, band: .overview, watch: true),
        Case(tags: ["railway": "funicular"], featureClass: .railway, band: .overview, watch: true),
        Case(tags: ["railway": "tram"], featureClass: .railway, band: .detail, watch: true),
        Case(tags: ["waterway": "river"], featureClass: .waterLine, band: .overview, watch: true),
        Case(tags: ["waterway": "canal"], featureClass: .waterLine, band: .mid, watch: true),
        Case(tags: ["waterway": "stream"], featureClass: .waterLine, band: .mid, watch: true),
        Case(tags: ["waterway": "ditch"], featureClass: .waterLine, band: .detail, watch: false),
        Case(tags: ["waterway": "drain"], featureClass: .waterLine, band: .detail, watch: false),
        Case(tags: ["natural": "water"], featureClass: .waterArea, band: .overview, watch: true),
        Case(tags: ["waterway": "riverbank"], featureClass: .waterArea, band: .overview, watch: true),
        Case(tags: ["landuse": "reservoir"], featureClass: .waterArea, band: .overview, watch: true),
        Case(tags: ["landuse": "basin"], featureClass: .waterArea, band: .overview, watch: true),
        Case(tags: ["natural": "wood"], featureClass: .forest, band: .overview, watch: true),
        Case(tags: ["landuse": "forest"], featureClass: .forest, band: .overview, watch: true),
        Case(tags: ["boundary": "administrative"], featureClass: .other, band: .detail, watch: false),
        Case(tags: ["boundary": "administrative", "admin_level": "4"], featureClass: .boundary, band: .overview, watch: false),
        Case(tags: ["boundary": "administrative", "admin_level": "7"], featureClass: .other, band: .detail, watch: false),
        Case(tags: ["boundary": "administrative", "admin_level": "2"], featureClass: .countryBorder, band: .overview, watch: false),
        Case(tags: ["boundary": "protected_area"], featureClass: .parkBorder, band: .overview, watch: false),
        Case(tags: ["boundary": "national_park"], featureClass: .parkBorder, band: .overview, watch: false),
        Case(tags: ["leisure": "nature_reserve"], featureClass: .parkBorder, band: .overview, watch: false),
        Case(tags: ["man_made": "pier"], featureClass: .pier, band: .mid, watch: false),
        Case(tags: ["man_made": "breakwater"], featureClass: .pier, band: .mid, watch: false),
        Case(tags: ["natural": "scrub"], featureClass: .landcover, band: .overview, watch: true),
        Case(tags: ["natural": "scree"], featureClass: .bareGround, band: .overview, watch: true),
        Case(tags: ["natural": "glacier"], featureClass: .glacier, band: .overview, watch: true),
        Case(tags: ["natural": "wetland"], featureClass: .wetland, band: .overview, watch: true),
        Case(tags: ["natural": "mud"], featureClass: .wetland, band: .overview, watch: true),
        Case(tags: ["natural": "bare_rock"], featureClass: .bareGround, band: .overview, watch: true),
        Case(tags: ["natural": "rock"], featureClass: .bareGround, band: .mid, watch: true),
        Case(tags: ["natural": "bedrock"], featureClass: .bareGround, band: .mid, watch: true),
        Case(tags: ["natural": "blockfield"], featureClass: .bareGround, band: .mid, watch: true),
        Case(tags: ["natural": "shale"], featureClass: .bareGround, band: .mid, watch: true),
        Case(tags: ["natural": "sand"], featureClass: .sand, band: .overview, watch: true),
        Case(tags: ["natural": "beach"], featureClass: .sand, band: .overview, watch: true),
        Case(tags: ["natural": "shingle"], featureClass: .bareGround, band: .overview, watch: true),
        Case(tags: ["natural": "grass"], featureClass: .landcover, band: .overview, watch: true),
        Case(tags: ["landuse": "cemetery"], featureClass: .landcover, band: .mid, watch: true),
        Case(tags: ["landuse": "brownfield"], featureClass: .landcover, band: .mid, watch: true),
        Case(tags: ["landuse": "greenfield"], featureClass: .landcover, band: .mid, watch: true),
        Case(tags: ["landuse": "pasture"], featureClass: .landcover, band: .overview, watch: true),
        Case(tags: ["landuse": "meadow"], featureClass: .landcover, band: .overview, watch: true),
        Case(tags: ["landuse": "farmland"], featureClass: .landcover, band: .overview, watch: true),
        Case(tags: ["landuse": "village_green"], featureClass: .landcover, band: .mid, watch: true),
        Case(tags: ["landuse": "farmyard"], featureClass: .landuseUrban, band: .overview, watch: false),
        Case(tags: ["natural": "shrubbery"], featureClass: .landcover, band: .overview, watch: true),
        Case(tags: ["natural": "cliff"], featureClass: .cliff, band: .mid, watch: false),
        Case(tags: ["natural": "coastline"], featureClass: .coastline, band: .overview, watch: false),
        Case(tags: ["place": "farm"], featureClass: .place, band: .detail, watch: false),
        Case(tags: ["place": "neighbourhood"], featureClass: .place, band: .detail, watch: false),
        Case(tags: ["railway": "subway"], featureClass: .railway, band: .detail, watch: false),
        Case(tags: ["railway": "level_crossing"], featureClass: .roadPoint, band: .detail, watch: false),
        Case(tags: ["railway": "switch"], featureClass: .roadPoint, band: .detail, watch: false),
        Case(tags: ["traffic_calming": "hump"], featureClass: .roadPoint, band: .detail, watch: false),
        Case(tags: ["power": "pole"], featureClass: .powerLine, band: .detail, watch: false),
        Case(tags: ["waterway": "dam"], featureClass: .waterLine, band: .detail, watch: false),
        Case(tags: ["addr:housenumber": "5", "addr:street": "Storgata"], featureClass: .address, band: .detail, watch: false),
        Case(tags: ["addr:city": "Oslo"], featureClass: .address, band: .detail, watch: false),
        Case(tags: ["highway": "footway", "footway": "sidewalk"], featureClass: .pavement, band: .detail, watch: false),
        Case(tags: ["landuse": "quarry"], featureClass: .bareGround, band: .overview, watch: true),
        Case(tags: ["leisure": "park"], featureClass: .landcover, band: .mid, watch: true),
        Case(tags: ["leisure": "pitch"], featureClass: .landcover, band: .mid, watch: true),
        Case(tags: ["landuse": "residential"], featureClass: .landuseUrban, band: .overview, watch: false),
        Case(tags: ["landuse": "military"], featureClass: .militaryArea, band: .overview, watch: false),
        Case(tags: ["landuse": "landfill"], featureClass: .landUse, band: .mid, watch: false),
        Case(tags: ["building": "yes"], featureClass: .building, band: .mid, watch: false),
        Case(tags: ["building": "house"], featureClass: .building, band: .mid, watch: false),
        Case(tags: ["building:part": "yes"], featureClass: .building, band: .detail, watch: false),
        Case(tags: ["amenity": "restaurant"], featureClass: .poi, band: .detail, watch: false),
        Case(tags: ["shop": "bakery"], featureClass: .poi, band: .detail, watch: false),
        Case(tags: ["tourism": "hotel"], featureClass: .poi, band: .detail, watch: false),
        Case(tags: ["historic": "ruins"], featureClass: .poi, band: .detail, watch: false),
        Case(tags: ["man_made": "tower"], featureClass: .poi, band: .detail, watch: false),
        Case(tags: ["emergency": "phone"], featureClass: .poi, band: .detail, watch: false),
        // Rule table version 2.
        Case(tags: ["power": "line"], featureClass: .powerLine, band: .mid, watch: true),
        Case(tags: ["power": "minor_line"], featureClass: .powerLine, band: .mid, watch: true),
        Case(tags: ["power": "cable"], featureClass: .powerLine, band: .mid, watch: true),
        Case(tags: ["power": "tower"], featureClass: .powerLine, band: .detail, watch: true),
        Case(tags: ["aerialway": "cable_car"], featureClass: .aerialway, band: .mid, watch: true),
        Case(tags: ["aerialway": "chair_lift"], featureClass: .aerialway, band: .mid, watch: true),
        Case(tags: ["aerialway": "t-bar"], featureClass: .aerialway, band: .mid, watch: true),
        Case(tags: ["aerialway": "station"], featureClass: .aerialway, band: .detail, watch: true),
        Case(tags: ["piste:type": "downhill"], featureClass: .piste, band: .mid, watch: true),
        Case(tags: ["piste:type": "nordic", "piste:difficulty": "easy"], featureClass: .piste, band: .mid, watch: true),
        Case(tags: ["piste:type": "something_new"], featureClass: .piste, band: .mid, watch: true),
        Case(tags: ["natural": "tree"], featureClass: .tree, band: .detail, watch: false),
        Case(tags: ["natural": "tree_row"], featureClass: .tree, band: .detail, watch: false),
        Case(tags: ["barrier": "fence"], featureClass: .barrier, band: .detail, watch: false),
        Case(tags: ["barrier": "gate"], featureClass: .barrier, band: .detail, watch: false),
        Case(tags: ["barrier": "something_new"], featureClass: .barrier, band: .detail, watch: false),
        Case(tags: ["highway": "bus_stop"], featureClass: .transportStop, band: .detail, watch: false),
        Case(tags: ["public_transport": "platform"], featureClass: .transportStop, band: .detail, watch: false),
        Case(tags: ["public_transport": "something_new"], featureClass: .transportStop, band: .detail, watch: false),
        Case(tags: ["railway": "station"], featureClass: .transportStop, band: .detail, watch: false),
        Case(tags: ["railway": "tram_stop"], featureClass: .transportStop, band: .detail, watch: false),
        Case(tags: ["highway": "crossing"], featureClass: .roadPoint, band: .detail, watch: false),
        Case(tags: ["highway": "traffic_signals"], featureClass: .roadPoint, band: .detail, watch: false),
        Case(tags: ["highway": "street_lamp"], featureClass: .roadPoint, band: .detail, watch: false),
        // Still not classified: pylons of lifts, wind turbines.
        Case(tags: ["aerialway": "pylon"], featureClass: .other, band: .detail, watch: false),
        Case(tags: ["power": "generator", "generator:source": "wind"], featureClass: .other, band: .detail, watch: false),
        Case(tags: ["barrier": "no"], featureClass: .other, band: .detail, watch: false),
        Case(tags: ["highway": "construction"], featureClass: .other, band: .detail, watch: false),
        Case(tags: ["highway": "proposed"], featureClass: .other, band: .detail, watch: false),
        Case(tags: ["place": "island"], featureClass: .other, band: .detail, watch: false),
        Case(tags: [:], featureClass: .other, band: .detail, watch: false),
    ]

    @Test("Each rule of the approved table", arguments: table)
    func rule(_ item: Case) {
        let result = classify(item.tags)
        #expect(result.featureClass == item.featureClass)
        #expect(result.minimumBand == item.band)
        #expect(result.showsOnWatch == item.watch)
    }

    @Test("Unnamed peaks are peaks too")
    func unnamedPeak() {
        #expect(classify(["natural": "peak"], .node).featureClass == .peak)
        #expect(classify(["natural": "peak", "name": "Naafkopf"], .node).showsOnWatch)
    }

    @Test("Every class is reachable, and class IDs are unique")
    func allClassesCovered() {
        // `sea` is made by the builder from the coastlines; no tags give it. The outline of a water area, and the sea part of a
        // park border, are made by the builder from the geometry, `roadArea` from a road that is an area, and `riverName` from the stretches of
        // a named river that lie in its own area.
        let produced = Set(Self.table.map(\.featureClass)).union([.sea, .roadArea, .waterEdge, .parkBorderSea, .riverName])
        #expect(produced == Set(FeatureClass.allCases))
        #expect(Set(FeatureClass.allCases.map(\.rawValue)).count == FeatureClass.allCases.count)
    }

    @Test("A hut that is also a building is a hut")
    func hutBeforeBuilding() {
        let result = classify(["tourism": "alpine_hut", "building": "yes"], .closedWay)
        #expect(result.featureClass == .poiAnchor && result.kind == .area)
    }

    @Test("A restaurant building is a building")
    func buildingBeforePOI() {
        #expect(classify(["building": "yes", "amenity": "restaurant"], .closedWay).featureClass == .building)
    }

    @Test("building=no is not a building")
    func buildingNo() {
        #expect(classify(["building": "no"]).featureClass == .other)
    }

    @Test("A protected area, also when it is a nature reserve, is a park border: a line, never a surface")
    func parkBorder() {
        #expect(classify(["boundary": "protected_area", "leisure": "nature_reserve"], .multipolygon).featureClass == .parkBorder)
        #expect(classify(["boundary": "national_park"], .closedWay).featureClass == .parkBorder)
        #expect(classify(["leisure": "nature_reserve"], .closedWay).featureClass == .parkBorder)
        #expect(classify(["boundary": "protected_area"], .closedWay).kind == .line)
        #expect(classify(["boundary": "protected_area"], .multipolygon).kind == .line)
        #expect(classify(["boundary": "administrative", "admin_level": "4"]).featureClass == .boundary)
    }

    @Test("A pier, a breakwater and a groyne are piers")
    func pier() {
        #expect(classify(["man_made": "pier"]).featureClass == .pier)
        #expect(classify(["man_made": "breakwater"]).featureClass == .pier)
        #expect(classify(["man_made": "pier", "floating": "yes"], .closedWay).kind == .area)
        #expect(classify(["man_made": "tower"], .node).featureClass == .poi)
    }

    @Test("Track grade goes into the subclass")
    func trackGrade() {
        #expect(classify(["highway": "track", "tracktype": "grade3"]).subclass == 3)
        #expect(classify(["highway": "track"]).subclass == 0)
        #expect(classify(["highway": "track", "tracktype": "bogus"]).subclass == 0)
    }

    @Test("Subclass holds the highway value, with bridge and tunnel bits")
    func subclassBits() {
        let plain = classify(["highway": "footway"])
        #expect(plain.subclass == 2)
        let bridge = classify(["highway": "footway", "bridge": "yes"])
        #expect(SubclassBits.isBridge(bridge.subclass) && !SubclassBits.isTunnel(bridge.subclass))
        #expect(SubclassBits.value(of: bridge.subclass) == 2)
        let tunnel = classify(["highway": "primary", "tunnel": "culvert"])
        #expect(SubclassBits.isTunnel(tunnel.subclass) && SubclassBits.value(of: tunnel.subclass) == 3)
        #expect(!SubclassBits.isBridge(classify(["highway": "path", "bridge": "no"]).subclass))
        // Not set on classes without casings.
        #expect(classify(["building": "yes", "bridge": "yes"]).subclass == 0)
    }

    @Test("Nodes are points, open ways lines, multipolygons areas")
    func kinds() {
        #expect(classify(["amenity": "drinking_water"], .node).kind == .point)
        #expect(classify(["highway": "path"], .openWay).kind == .line)
        #expect(classify(["landuse": "forest"], .openWay).kind == .line)
        #expect(classify(["natural": "water", "type": "multipolygon"], .multipolygon).kind == .area)
    }

    @Test("Closed ways: area keys make areas, highways and barriers stay lines")
    func closedWays() {
        #expect(classify(["building": "yes"], .closedWay).kind == .area)
        #expect(classify(["landuse": "forest"], .closedWay).kind == .area)
        #expect(classify(["natural": "water"], .closedWay).kind == .area)
        #expect(classify(["leisure": "park"], .closedWay).kind == .area)
        #expect(classify(["highway": "residential"], .closedWay).kind == .line)
        #expect(classify(["highway": "pedestrian", "area": "yes"], .closedWay).kind == .area)
        #expect(classify(["highway": "pedestrian", "area": "yes"], .closedWay).featureClass == .roadArea)
        #expect(classify(["barrier": "fence"], .closedWay).kind == .line)
        #expect(classify(["railway": "rail"], .closedWay).kind == .line)
        #expect(classify(["boundary": "administrative"], .closedWay).kind == .line)
        #expect(classify(["boundary": "protected_area"], .closedWay).kind == .line, "the border of a park is a line")
        #expect(classify(["boundary": "protected_area"], .closedWay).featureClass == .parkBorder)
        #expect(classify(["waterway": "riverbank"], .closedWay).kind == .area)
        #expect(classify([:], .closedWay).kind == .line)
    }

    @Test("Linear natural values stay lines when closed")
    func linearNatural() {
        for value in ["coastline", "cliff", "ridge", "arete", "tree_row", "valley"] {
            #expect(classify(["natural": value], .closedWay).kind == .line, "\(value)")
        }
        #expect(classify(["man_made": "pipeline"], .closedWay).kind == .line)
        #expect(classify(["man_made": "tower"], .closedWay).kind == .area)
    }

    @Test("area=no wins over area keys, area=yes over lines")
    func explicitArea() {
        #expect(classify(["landuse": "forest", "area": "no"], .closedWay).kind == .line)
        #expect(classify(["barrier": "fence", "area": "yes"], .closedWay).kind == .area)
    }

    @Test("The first matching rule wins, independent of tag order")
    func priority() {
        let a = classify(["highway": "path", "waterway": "stream"])
        #expect(a.featureClass == .path)
        let b = classify(["waterway": "stream", "highway": "path"])
        #expect(a == b)
    }

    @Test("A ski trail that is also a hiking path stays a path, and bridges and tunnels are marked on lifts and lines")
    func version2Priority() {
        #expect(classify(["highway": "path", "piste:type": "nordic"]).featureClass == .path)
        #expect(classify(["highway": "track", "piste:type": "nordic"]).featureClass == .track)
        #expect(classify(["piste:type": "nordic"]).subclass == 2)
        #expect(classify(["aerialway": "gondola"]).subclass == 2 && classify(["aerialway": "station"], .node).kind == .point)
        #expect(classify(["natural": "tree"], .node).kind == .point && classify(["natural": "tree_row"], .closedWay).kind == .line)
        // A bus stop that is also a shelter is a shelter, as before; a platform footway is still a path.
        #expect(classify(["highway": "bus_stop", "amenity": "shelter"], .node).featureClass == .poiAnchor)
        #expect(classify(["highway": "footway", "public_transport": "platform"]).featureClass == .path)
        // A barrier that is a closed way stays a line.
        #expect(classify(["barrier": "fence"], .closedWay).kind == .line)
        // Power towers are points and lines stay lines.
        #expect(classify(["power": "tower"], .node).kind == .point && classify(["power": "line"], .openWay).kind == .line)
    }

    @Test("Of the administrative boundaries only national borders and the level of states are kept")
    func countryBorder() {
        let border = classify(["boundary": "administrative", "admin_level": "2"], .openWay)
        #expect(border.featureClass == .countryBorder && border.kind == .line)
        #expect(border.minimumBand == .overview && !border.showsOnWatch)
        #expect(classify(["boundary": "administrative", "admin_level": "4"], .openWay).featureClass == .boundary, "states and counties")
        for level in ["3", "5", "6", "7", "8", "9", "10", ""] {
            #expect(classify(["boundary": "administrative", "admin_level": level], .openWay).featureClass == .other, "level \(level)")
        }
        #expect(classify(["boundary": "administrative"], .openWay).featureClass == .other, "no level")
        // Protected areas and national parks are park borders, whatever else they say.
        #expect(classify(["boundary": "protected_area", "admin_level": "2"], .openWay).featureClass == .parkBorder)
        // A border in the sea between two countries is a national border (the Idefjord between Norway and Sweden)...
        let fjord = classify(["boundary": "administrative", "admin_level": "2", "maritime": "yes"], .openWay)
        #expect(fjord.featureClass == .countryBorder)
        // ...but the limit of the territorial waters, or of an economic zone, is not drawn.
        for type in ["territorial", "eez", "contiguous"] {
            let limit = classify(["boundary": "administrative", "admin_level": "2", "maritime": "yes", "border_type": type], .openWay)
            #expect(limit.featureClass == .other, "border type \(type)")
        }
        #expect(classify(["boundary": "administrative", "admin_level": "2", "border_type": "nation"], .openWay).featureClass == .countryBorder)
    }

    @Test("A road or path that is an area is a road area to fill, not a line to stroke")
    func roadAreas() {
        let yard = classify(["highway": "service", "area": "yes", "landuse": "industrial"], .closedWay)
        #expect(yard.featureClass == .roadArea && yard.kind == .area)
        #expect(yard.minimumBand == .detail && !yard.showsOnWatch)
        #expect(classify(["highway": "pedestrian", "area": "yes"], .closedWay).featureClass == .roadArea)
        #expect(classify(["highway": "footway", "area": "yes"], .closedWay).featureClass == .roadArea)
        #expect(classify(["highway": "pedestrian"], .multipolygon).featureClass == .roadArea, "a road mapped as a multipolygon")
        // The same tags on a line, and a closed road, stay roads.
        #expect(classify(["highway": "service"], .openWay).featureClass == .roadService)
        #expect(classify(["highway": "service"], .closedWay).featureClass == .roadService && classify(["highway": "service"], .closedWay).kind == .line)
        #expect(classify(["highway": "residential", "area": "no"], .closedWay).featureClass == .roadMinor)
    }

    @Test("A place keeps its subclass whatever its population, and the population reads as a number")
    func populationOfAPlace() {
        #expect(classify(["place": "town", "population": "9000"], .openWay).subclass == 2)
        #expect(PlaceRank.population("12 345") == 12_345 && PlaceRank.population("12,345") == 12_345)
        #expect(PlaceRank.population("12.345") == 12_345 && PlaceRank.population("many") == nil && PlaceRank.population(nil) == nil)
    }

    @Test("A coastline is a coastline line even when the way is also a place or another area")
    func coastlineWins() {
        for extra in [["place": "islet"], ["place": "island", "name": "Holmen"], ["natural": "coastline", "landuse": "grass"]] {
            var tags = extra
            tags["natural"] = "coastline"
            let result = classify(tags, .closedWay)
            #expect(result.featureClass == .coastline && result.kind == .line, "\(extra)")
            #expect(result.minimumBand == .overview && !result.showsOnWatch)
        }
        #expect(classify(["natural": "coastline"], .openWay).kind == .line)
        #expect(classify(["place": "islet"], .closedWay).featureClass == .place, "an islet without a coastline tag stays a place")
    }

    @Test("A sidewalk or a crossing is pavement; other footways stay paths")
    func pavement() {
        for kind in ["sidewalk", "crossing", "traffic_island", "access_aisle"] {
            let result = classify(["highway": "footway", "footway": kind], .openWay)
            #expect(result.featureClass == .pavement && result.kind == .line, "footway=\(kind)")
            #expect(result.minimumBand == .detail && !result.showsOnWatch)
        }
        #expect(classify(["highway": "footway"], .openWay).featureClass == .path)
        #expect(classify(["highway": "footway", "footway": "link"], .openWay).featureClass == .path)
        #expect(classify(["highway": "path", "footway": "sidewalk"], .openWay).featureClass == .path)
        // A bridge keeps its bit, and the footway value stays in the subclass.
        let bridge = classify(["highway": "footway", "footway": "sidewalk", "bridge": "yes"], .openWay)
        #expect(bridge.featureClass == .pavement && bridge.subclass == (2 | SubclassBits.bridge))
    }

    @Test("A shop with an address is a point of interest; only the address alone is an address")
    func addresses() {
        #expect(classify(["shop": "bakery", "addr:street": "Storgata"], .node).featureClass == .poi)
        #expect(classify(["building": "yes", "addr:housenumber": "5"], .closedWay).featureClass == .building)
        #expect(classify(["addr:housenumber": "5"], .node).featureClass == .address)
        #expect(classify(["name": "Stone"], .node).featureClass == .other)
    }

    @Test("Every other landuse value, and dune, moor, tundra and bog, are landUse from the mid band; a building or a shop keeps its class")
    func landUseCatchAll() {
        for value in ["landfill", "animal_keeping", "plant_nursery", "greenhouse_horticulture", "religious", "aquaculture", "winter_sports", "depot", "harbour", "something_new"] {
            let outcome = classify(["landuse": value], .closedWay)
            #expect(outcome.featureClass == .landUse && outcome.minimumBand == .mid && !outcome.showsOnWatch && outcome.kind == .area, "\(value)")
        }
        for value in ["dune", "moor", "tundra", "bog"] {
            #expect(classify(["natural": value], .closedWay).featureClass == .landUse, "\(value)")
        }
        #expect(classify(["landuse": "religious", "building": "yes"], .closedWay).featureClass == .building)
        #expect(classify(["landuse": "religious", "amenity": "place_of_worship"], .closedWay).featureClass == .poi)
        #expect(classify(["landuse": "landfill", "addr:street": "Weg"], .closedWay).featureClass == .landUse)
        #expect(classify(["landuse": "forest"], .closedWay).featureClass == .forest && classify(["landuse": "residential"], .closedWay).featureClass == .landuseUrban)
    }

    @Test("A node with a land cover tag is not stored as a surface: a single rock is an unclassified point")
    func nodesOfSurfaceTags() {
        for tags in [["natural": "rock"], ["natural": "glacier"], ["natural": "wetland"], ["natural": "sand"], ["natural": "scrub"], ["leisure": "pitch"],
            ["landuse": "landfill"], ["natural": "dune"]] {
            let node = classify(tags, .node)
            #expect(node.featureClass == .other && node.kind == .point, "\(tags)")
            #expect(classify(tags, .closedWay).featureClass != .other, "the area with the same tags keeps its class: \(tags)")
        }
    }

    @Test("The rule table version is 21, and the class IDs of earlier versions did not change")
    func version() {
        #expect(FeatureClassifier.version == 21)
        #expect(FeatureClass.address.rawValue == 25 && FeatureClass.pavement.rawValue == 26 && FeatureClass.cliff.rawValue == 27)
        #expect(FeatureClass.countryBorder.rawValue == 24 && FeatureClass.roadPoint.rawValue == 23)
        #expect(FeatureClass.peak.rawValue == 12 && FeatureClass.boundary.rawValue == 16 && FeatureClass.other.rawValue == 0)
        #expect(FeatureClass.militaryArea.rawValue == 36 && FeatureClass.glacier.rawValue == 37)
        #expect(FeatureClass.bareGround.rawValue == 38 && FeatureClass.wetland.rawValue == 39)
        #expect(FeatureClass.sand.rawValue == 40 && FeatureClass.landUse.rawValue == 41 && FeatureClass.riverName.rawValue == 42 && FeatureClass.allCases.count == 43)
        // The subclass numbers of the values that moved out of landcover (rule table 18) are fixed by this table.
        #expect(classify(["natural": "scree"], .closedWay).subclass == 2 && classify(["natural": "rock"], .closedWay).subclass == 6)
        #expect(classify(["natural": "beach"], .closedWay).subclass == 2 && classify(["natural": "wetland"], .closedWay).subclass == 1)
        #expect(classify(["landuse": "quarry"], .closedWay).subclass == 10 && classify(["natural": "glacier"], .closedWay).subclass == 1)
    }
}
