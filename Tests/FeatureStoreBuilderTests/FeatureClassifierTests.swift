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
        Case(tags: ["highway": "residential"], featureClass: .roadMinor, band: .detail, watch: true),
        Case(tags: ["highway": "service"], featureClass: .roadMinor, band: .detail, watch: true),
        Case(tags: ["highway": "pedestrian"], featureClass: .roadMinor, band: .detail, watch: true),
        Case(tags: ["railway": "rail"], featureClass: .railway, band: .overview, watch: true),
        Case(tags: ["railway": "funicular"], featureClass: .railway, band: .overview, watch: true),
        Case(tags: ["railway": "tram"], featureClass: .railway, band: .detail, watch: true),
        Case(tags: ["waterway": "river"], featureClass: .waterLine, band: .overview, watch: true),
        Case(tags: ["waterway": "canal"], featureClass: .waterLine, band: .overview, watch: true),
        Case(tags: ["waterway": "stream"], featureClass: .waterLine, band: .mid, watch: true),
        Case(tags: ["waterway": "ditch"], featureClass: .waterLine, band: .detail, watch: false),
        Case(tags: ["waterway": "drain"], featureClass: .waterLine, band: .detail, watch: false),
        Case(tags: ["natural": "water"], featureClass: .waterArea, band: .overview, watch: true),
        Case(tags: ["waterway": "riverbank"], featureClass: .waterArea, band: .overview, watch: true),
        Case(tags: ["landuse": "reservoir"], featureClass: .waterArea, band: .overview, watch: true),
        Case(tags: ["landuse": "basin"], featureClass: .waterArea, band: .overview, watch: true),
        Case(tags: ["natural": "wood"], featureClass: .forest, band: .overview, watch: true),
        Case(tags: ["landuse": "forest"], featureClass: .forest, band: .overview, watch: true),
        Case(tags: ["boundary": "administrative"], featureClass: .boundary, band: .overview, watch: false),
        Case(tags: ["boundary": "protected_area"], featureClass: .boundary, band: .overview, watch: false),
        Case(tags: ["boundary": "national_park"], featureClass: .boundary, band: .overview, watch: false),
        Case(tags: ["natural": "scrub"], featureClass: .landcover, band: .mid, watch: true),
        Case(tags: ["natural": "scree"], featureClass: .landcover, band: .mid, watch: true),
        Case(tags: ["natural": "glacier"], featureClass: .landcover, band: .mid, watch: true),
        Case(tags: ["natural": "wetland"], featureClass: .landcover, band: .mid, watch: true),
        Case(tags: ["landuse": "meadow"], featureClass: .landcover, band: .mid, watch: true),
        Case(tags: ["landuse": "farmland"], featureClass: .landcover, band: .mid, watch: true),
        Case(tags: ["landuse": "quarry"], featureClass: .landcover, band: .mid, watch: true),
        Case(tags: ["leisure": "park"], featureClass: .landcover, band: .mid, watch: true),
        Case(tags: ["leisure": "pitch"], featureClass: .landcover, band: .mid, watch: true),
        Case(tags: ["landuse": "residential"], featureClass: .landuseUrban, band: .mid, watch: false),
        Case(tags: ["landuse": "military"], featureClass: .landuseUrban, band: .mid, watch: false),
        Case(tags: ["building": "yes"], featureClass: .building, band: .detail, watch: false),
        Case(tags: ["building": "house"], featureClass: .building, band: .detail, watch: false),
        Case(tags: ["building:part": "yes"], featureClass: .building, band: .detail, watch: false),
        Case(tags: ["amenity": "restaurant"], featureClass: .poi, band: .detail, watch: false),
        Case(tags: ["shop": "bakery"], featureClass: .poi, band: .detail, watch: false),
        Case(tags: ["tourism": "hotel"], featureClass: .poi, band: .detail, watch: false),
        Case(tags: ["historic": "ruins"], featureClass: .poi, band: .detail, watch: false),
        Case(tags: ["man_made": "tower"], featureClass: .poi, band: .detail, watch: false),
        Case(tags: ["emergency": "phone"], featureClass: .poi, band: .detail, watch: false),
        Case(tags: ["barrier": "gate"], featureClass: .other, band: .detail, watch: false),
        Case(tags: ["highway": "construction"], featureClass: .other, band: .detail, watch: false),
        Case(tags: ["highway": "proposed"], featureClass: .other, band: .detail, watch: false),
        Case(tags: ["power": "line"], featureClass: .other, band: .detail, watch: false),
        Case(tags: ["waterway": "dam"], featureClass: .other, band: .detail, watch: false),
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
        let produced = Set(Self.table.map(\.featureClass))
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

    @Test("A boundary protected area that is also a nature reserve is a boundary")
    func boundaryBeforeLandcover() {
        #expect(classify(["boundary": "protected_area", "leisure": "nature_reserve"], .multipolygon).featureClass == .boundary)
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
        #expect(classify(["highway": "pedestrian", "area": "yes"], .closedWay).featureClass == .roadMinor)
        #expect(classify(["barrier": "fence"], .closedWay).kind == .line)
        #expect(classify(["railway": "rail"], .closedWay).kind == .line)
        #expect(classify(["boundary": "administrative"], .closedWay).kind == .line)
        #expect(classify(["boundary": "protected_area"], .closedWay).kind == .area)
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

    @Test("The rule table version is set")
    func version() {
        #expect(FeatureClassifier.version == 1)
    }
}
