import FeatureStore
import OSMPBF

extension FeatureStoreBuilder {
    /// Stores every way as a line or area feature, except those a multipolygon already holds.
    func storeWays(
        of extract: OSMExtract, suppressed: Set<Int64>, shore: inout ShoreContext, into emitter: inout FeatureEmitter
    ) throws {
        // Built when the first footway needs it: an extract without footways never pays for it.
        var roads: RoadIndex?
        var town: TownIndex?
        for position in extract.ways.indices {
            if position % 4096 == 0 { try Task.checkCancellation() }
            let id = extract.ways.ids[position]
            if suppressed.contains(id) {
                emitter.report.waysSuppressed += 1
                continue
            }
            var (runs, gaps) = Self.runs(ofWayAt: position, in: extract)
            if gaps > 0 { emitter.report.waysWithMissingNodes += 1 }
            guard !runs.isEmpty else {
                emitter.report.waysWithoutGeometry += 1
                continue
            }
            let nodeIDs = extract.ways.nodeIDs(at: position)
            let isClosed = gaps == 0 && nodeIDs.count >= 4 && nodeIDs.first == nodeIDs.last
            let tags = extract.ways.tags(at: position)
            var classification = classifier.classify(tags, shape: isClosed ? .closedWay : .openWay)
            // A footway beside a road is a sidewalk, tagged or not.
            if Self.mayBeASidewalk(tags, classification) {
                if roads == nil { roads = RoadIndex(extract: extract, classifier: classifier) }
                // A footway beside a road wins over one in a town; the two are counted apart in the report.
                let pavement = Classification(
                    featureClass: .pavement, subclass: classification.subclass, kind: classification.kind, minimumBand: .detail,
                    showsOnWatch: false)
                if roads?.isBesideARoad(runs) == true {
                    classification = pavement
                    emitter.report.footwaysBesideRoads += 1
                } else {
                    if town == nil {
                        town = TownIndex(extract: extract, classifier: classifier)
                        emitter.report.townAreas = town?.town.polygons.count ?? 0
                        emitter.report.greenAreas = town?.green.polygons.count ?? 0
                    }
                    if town?.isInTown(runs) == true {
                        classification = pavement
                        emitter.report.footwaysInTown += 1
                    }
                }
            }
            switch classification.featureClass {
            case .parkBorder:
                try storeParkBorder(
                    classification, objectType: .way, objectID: id, tags: tags.orderedTags, lines: runs, shore: shore, into: &emitter)
                emitter.report.waysStored += 1
                continue
            case .coastline:
                // The coastline that closes the mouth of a river runs through the water of the river: it is not a shore.
                let result = shore.coastline(runs)
                emitter.report.coastlineStretchesInRivers += result.dropped
                runs = result.kept
            case .waterLine where classification.kind == .line && (1...5).contains(SubclassBits.value(of: classification.subclass)):
                // The centre line of a river is not drawn through the river's own area.
                let result = shore.waterLine(runs)
                emitter.report.waterLineStretchesInWater += result.dropped
                runs = result.kept
            default:
                break
            }
            guard !runs.isEmpty else { continue }
            let geometry: FeatureSpec.Geometry = classification.kind == .area ? .rings([runs[0]]) : .lines(runs)
            try emitter.emit(FeatureSpec(
                classification: classification, objectType: .way, objectID: id, tags: tags.orderedTags, geometry: geometry))
            emitter.report.waysStored += 1
            if classification.featureClass == .waterArea, classification.kind == .area, isClosed {
                try storeWaterEdge(
                    of: [runs[0]], classification, objectType: .way, objectID: id, tags: tags.orderedTags, shore: &shore,
                    into: &emitter)
            }
        }
    }

    /// The tags that say a footway is a trail or a route, which a road beside it does not change.
    private static let trailKeys = ["sac_scale", "trail_visibility", "mtb:scale", "informal", "trailblazed", "hiking"]

    /// Whether a way is a footway that could be a sidewalk: a `highway=footway` of the path class with no tag of a trail.
    private static func mayBeASidewalk(_ tags: some ClassifierTags, _ classification: Classification) -> Bool {
        classification.featureClass == .path && tags.value(forKey: "highway") == "footway"
            && !trailKeys.contains { tags.value(forKey: $0) != nil }
    }
}
