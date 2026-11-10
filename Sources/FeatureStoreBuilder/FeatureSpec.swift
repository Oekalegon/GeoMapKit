import FeatureStore
import OSMPBF

/// Everything the emitter needs to store one feature in all its bands and cells.
struct FeatureSpec {
    enum Geometry {
        case point(PackedPoint)
        /// Open lines; each is clipped separately and gets its own pieces.
        case lines([[PackedPoint]])
        /// Closed rings of one area; fill with the even-odd rule.
        case rings([[PackedPoint]])
    }

    var classification: Classification
    var objectType: StoredObjectType
    var objectID: Int64
    var tags: [OSMTag]
    /// The name to store when the tags have none, for a feature named after something else (a border after the regions it
    /// separates).
    var fallbackName: String?
    var geometry: Geometry
    /// Flags added to every piece, for example `incomplete`.
    var extraFlags: FeatureFlags = []
    /// The last band the feature is stored in; the first is the `minimumBand` of its classification. A feature that another one
    /// replaces from a finer band (the centre line of a river in a thin water area, which the area replaces from the mid band) ends
    /// before it.
    var lastBand: ZoomBand = .detail
}
