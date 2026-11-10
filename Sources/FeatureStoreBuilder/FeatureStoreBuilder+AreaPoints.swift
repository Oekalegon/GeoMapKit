import FeatureStore
import OSMPBF

extension FeatureStoreBuilder {
    /// Stores a point inside an area for the marker and the name of a shop, a church, a hut or a station that is mapped as an outline.
    ///
    /// The renderer draws the marker and the name of `poi`, `poiAnchor` and `transportStop` for points only, and an area gets a name only
    /// if its own class has a label style (`waterArea` has, `building` and the land cover classes have not). So the building of a
    /// church had no marker and no name. The point is the pole of inaccessibility of the area (`PolygonPole`).
    ///
    /// - A `poi` is stored only if the area has a name: a parking lot or a pitch with no name would be a dot with nothing to say. A hut,
    ///   a shelter, a viewpoint (`poiAnchor`) or a station (`transportStop`) is stored whether it has a name or not.
    /// - A `waterArea` is left out: its name is written in the water already.
    ///
    /// - Parameters:
    ///   - primary: The class of the area.
    ///   - tags: The tags of the area.
    ///   - objectType: Way or relation.
    ///   - objectID: The OSM ID.
    ///   - rings: The rings of the area (a multipolygon: the largest polygon).
    ///   - emitter: Where the point is stored.
    func storeAreaPoint(
        primary: FeatureClass, tags: [OSMTag], objectType: StoredObjectType, objectID: Int64, rings: [[PackedPoint]],
        into emitter: inout FeatureEmitter
    ) throws {
        guard primary != .waterArea else { return }
        let array = ClassifierTagArray(tags)
        guard let point = classifier.pointClass(array) else { return }
        if point.featureClass == .poi, (array.value(forKey: "name") ?? "").isEmpty { return }
        guard let pole = PolygonPole.find(in: rings) else { return }
        try emitter.emit(FeatureSpec(
            classification: point, objectType: objectType, objectID: objectID, tags: tags, geometry: .point(pole)))
        emitter.report.areaPoints += 1
    }
}
