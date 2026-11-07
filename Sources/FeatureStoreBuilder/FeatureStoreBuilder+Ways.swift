import FeatureStore
import OSMPBF

extension FeatureStoreBuilder {
    /// Stores every way as a line or area feature, except those a multipolygon already holds.
    func storeWays(of extract: OSMExtract, suppressed: Set<Int64>, into emitter: inout FeatureEmitter) throws {
        // Built when the first footway needs it: an extract without footways never pays for it.
        var roads: RoadIndex?
        for position in extract.ways.indices {
            if position % 4096 == 0 { try Task.checkCancellation() }
            let id = extract.ways.ids[position]
            if suppressed.contains(id) {
                emitter.report.waysSuppressed += 1
                continue
            }
            let (runs, gaps) = Self.runs(ofWayAt: position, in: extract)
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
                if roads?.isBesideARoad(runs) == true {
                    classification = Classification(
                        featureClass: .pavement, subclass: classification.subclass, kind: classification.kind, minimumBand: .detail,
                        showsOnWatch: false)
                    emitter.report.footwaysBesideRoads += 1
                }
            }
            let geometry: FeatureSpec.Geometry = classification.kind == .area ? .rings([runs[0]]) : .lines(runs)
            try emitter.emit(FeatureSpec(
                classification: classification, objectType: .way, objectID: id, tags: tags.orderedTags, geometry: geometry))
            emitter.report.waysStored += 1
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
