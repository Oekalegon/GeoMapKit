import FeatureStore
import OSMPBF

extension FeatureStoreBuilder {
    /// Stores the border of a protected area as lines: the stretches on land as `parkBorder`, those in the sea as `parkBorderSea`.
    ///
    /// - Parameters:
    ///   - classification: The classification of the area, of class `parkBorder`.
    ///   - lines: The rings or outlines of the area.
    ///   - extraFlags: Flags for every piece, for example `incomplete`.
    func storeParkBorder(
        _ classification: Classification, objectType: StoredObjectType, objectID: Int64, tags: [OSMTag], lines: [[PackedPoint]],
        extraFlags: FeatureFlags = [], shore: ShoreContext, into emitter: inout FeatureEmitter
    ) throws {
        let (land, inSea) = shore.parkBorder(lines)
        emitter.report.parkBorderStretchesInSea += inSea.count
        for (featureClass, stretches) in [(FeatureClass.parkBorder, land), (FeatureClass.parkBorderSea, inSea)] where !stretches.isEmpty {
            let part = Classification(
                featureClass: featureClass, subclass: classification.subclass, kind: .line,
                minimumBand: classification.minimumBand, showsOnWatch: classification.showsOnWatch)
            try emitter.emit(FeatureSpec(
                classification: part, objectType: objectType, objectID: objectID, tags: tags, geometry: .lines(stretches),
                extraFlags: extraFlags))
        }
    }

    /// Stores the outline of a lake, a fjord or a river as lines of class `waterEdge`, left out where a coastline lies.
    func storeWaterEdge(
        of rings: [[PackedPoint]], _ classification: Classification, objectType: StoredObjectType, objectID: Int64,
        tags: [OSMTag], shore: inout ShoreContext, into emitter: inout FeatureEmitter
    ) throws {
        let edge = shore.outline(of: rings)
        guard !edge.isEmpty else { return }
        let outline = Classification(
            featureClass: .waterEdge, subclass: classification.subclass, kind: .line, minimumBand: classification.minimumBand,
            showsOnWatch: false)
        try emitter.emit(FeatureSpec(
            classification: outline, objectType: objectType, objectID: objectID, tags: tags, geometry: .lines(edge)))
    }
}
