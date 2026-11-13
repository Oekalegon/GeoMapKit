import FeatureStore
import OSMPBF

extension FeatureStoreBuilder {
    /// Stores every way as a line or area feature, except those a multipolygon already holds.
    func storeWays(
        of extract: OSMExtract, suppressed: Set<Int64>, borders: inout BorderNames?, shore: inout ShoreContext,
        into emitter: inout FeatureEmitter
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
            // The limit of the territorial waters is no border, but the agreed line between two countries is one, although it carries the
            // same tag (the Norway to Sweden line in the Iddefjord and the Skagerrak, and the Evros river between Greece and Turkey, which
            // is mapped with `border_type=territorial` and `waterway=river`): it is a member of the relations of both countries, a limit
            // is a member of one. This holds whatever else the way is: the tags without `border_type` then decide, for the class and for
            // the overlays below. The feature keeps all its raw tags, `border_type` included: the renderer uses classes only. A coastline
            // is left out: the shore is no border, whatever the relations say.
            var sharedLine: ClassifierTagArray?
            if tags.value(forKey: "boundary") == "administrative", tags.value(forKey: "admin_level") == "2", classifier.isSeaLimit(tags),
                classification.featureClass != .coastline
            {
                if borders == nil { borders = BorderNames(extract: extract, classifier: classifier) }
                if (borders?.countryRelationCount(ofWay: id) ?? 0) >= 2 {
                    let plain = ClassifierTagArray(tags.orderedTags.filter { $0.key != "border_type" })
                    sharedLine = plain
                    classification = classifier.classify(plain, shape: isClosed ? .closedWay : .openWay)
                }
            }
            // The border of a country is often a relation whose ways carry no border tags of their own (most of the land border of
            // Finland and Russia, and of Norway and Russia, is mapped so): a way with no class of its own that is a member of a
            // national border relation is a border. A state border works in the same way. A way tagged `boundary=administrative`
            // with no `admin_level` (the Finnish border at the tripoint with Norway) has no class of its own either.
            if classification.featureClass == .other,
                tags.value(forKey: "boundary") == nil
                    || (tags.value(forKey: "boundary") == "administrative" && tags.value(forKey: "admin_level") == nil)
            {
                if borders == nil { borders = BorderNames(extract: extract, classifier: classifier) }
                if let inherited = borders?.classOfUntaggedBorder(ofWay: id) {
                    let plain = [OSMTag(key: "boundary", value: "administrative"), OSMTag(key: "admin_level", value: inherited == .countryBorder ? "2" : "4")]
                    classification = classifier.classify(ClassifierTagArray(plain), shape: .openWay)
                    emitter.report.waysTakingBorderFromRelation += 1
                }
            }
            // A way is more than its primary class: a stream that the border follows, a forest that is a nature reserve, a track with a
            // piste (see `FeatureClassifier.overlays`). The overlay is stored as well, on the whole way. A way that is a member of a
            // national or state border relation is a border whatever else it is (the border of Ireland follows streams and a river that
            // carry no border tag), unless it is tagged as the limit of an area of sea, or is a coastline: the relations of a country or
            // a region often have the coast as members (1,991 coastline ways in the relations of the Danish file), and the shore is no
            // border.
            var overlays = sharedLine.map { classifier.overlays($0, primary: classification.featureClass) }
                ?? classifier.overlays(tags, primary: classification.featureClass)
            if classification.featureClass != .countryBorder, classification.featureClass != .boundary,
                !overlays.contains(where: { $0.featureClass == .countryBorder || $0.featureClass == .boundary }),
                !classifier.isSeaLimit(tags)
            {
                if borders == nil { borders = BorderNames(extract: extract, classifier: classifier) }
                if classification.featureClass != .other, classification.featureClass != .coastline,
                    let inherited = borders?.classOfUntaggedBorder(ofWay: id)
                {
                    let plain = [OSMTag(key: "boundary", value: "administrative"), OSMTag(key: "admin_level", value: inherited == .countryBorder ? "2" : "4")]
                    overlays.append(classifier.classify(ClassifierTagArray(plain), shape: .openWay))
                }
            }
            for overlay in overlays {
                if overlay.featureClass == .parkBorder {
                    try storeParkBorder(overlay, objectType: .way, objectID: id, tags: tags.orderedTags, lines: runs, shore: shore, into: &emitter)
                } else {
                    var overlayName: String?
                    if (overlay.featureClass == .countryBorder || overlay.featureClass == .boundary), tags.value(forKey: "name") == nil {
                        if borders == nil { borders = BorderNames(extract: extract, classifier: classifier) }
                        overlayName = borders?.name(ofWay: id, as: overlay.featureClass)
                    }
                    try emitter.emit(FeatureSpec(
                        classification: overlay, objectType: .way, objectID: id, tags: tags.orderedTags, fallbackName: overlayName,
                        geometry: .lines(runs)))
                }
                emitter.report.overlayFeatures += 1
            }
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
                // Its name is kept: the stretches in the water are stored as `riverName` lines, which are not drawn but carry the name, so a
                // wide river is named along its course though the area is what is drawn.
                // A thin or small area is in the mid and detail bands only: there the line is not drawn, as in a large area, but in the
                // overview band the line stays, since the area is not drawn there (the area and the line drawn together look like a river
                // with a line down its middle).
                let result = shore.waterLineStretches(runs)
                emitter.report.waterLineStretchesInWater += result.inWater.count
                emitter.report.waterLineStretchesInThinWater += result.inThinWater.count
                runs = result.kept
                let name = tags.value(forKey: "name") ?? ""
                if !result.inWater.isEmpty, !name.isEmpty {
                    try emitter.emit(FeatureSpec(
                        classification: Classification(
                            featureClass: .riverName, subclass: classification.subclass, kind: .line, minimumBand: .overview, showsOnWatch: false),
                        objectType: .way, objectID: id, tags: tags.orderedTags, geometry: .lines(result.inWater)))
                    emitter.report.riverNameStretches += result.inWater.count
                }
                if !result.inThinWater.isEmpty {
                    var overviewLine = FeatureSpec(
                        classification: classification, objectType: .way, objectID: id, tags: tags.orderedTags,
                        geometry: .lines(result.inThinWater))
                    overviewLine.lastBand = .overview
                    try emitter.emit(overviewLine)
                    if !name.isEmpty {
                        try emitter.emit(FeatureSpec(
                            classification: Classification(
                                featureClass: .riverName, subclass: classification.subclass, kind: .line, minimumBand: .mid, showsOnWatch: false),
                            objectType: .way, objectID: id, tags: tags.orderedTags, geometry: .lines(result.inThinWater)))
                        emitter.report.riverNameStretches += result.inThinWater.count
                    }
                }
            default:
                break
            }
            guard !runs.isEmpty else { continue }
            if classification.featureClass == .waterArea, classification.kind == .area {
                classification = WaterSize.adjusted(classification, rings: [runs[0]])
            }
            let geometry: FeatureSpec.Geometry = classification.kind == .area ? .rings([runs[0]]) : .lines(runs)
            var borderName: String?
            if classification.featureClass == .countryBorder || classification.featureClass == .boundary,
                tags.value(forKey: "name") == nil
            {
                if borders == nil { borders = BorderNames(extract: extract, classifier: classifier) }
                borderName = borders?.name(ofWay: id, as: classification.featureClass)
            }
            try emitter.emit(FeatureSpec(
                classification: classification, objectType: .way, objectID: id, tags: tags.orderedTags,
                fallbackName: borderName, geometry: geometry))
            emitter.report.waysStored += 1
            if classification.kind == .area {
                try storeAreaPoint(
                    primary: classification.featureClass, tags: tags.orderedTags, objectType: .way, objectID: id, rings: [runs[0]],
                    into: &emitter)
            }
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
