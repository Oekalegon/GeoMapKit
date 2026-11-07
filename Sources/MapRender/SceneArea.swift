import FeatureStore

/// One piece of an area ready to draw, in screen points.
///
/// An area that crosses cell borders comes as one piece per cell. Each piece is filled on its own and its
/// ``outline`` leaves out the edges that lie on a cell border, so no seams are stroked.
public struct SceneArea: Sendable, Equatable {
    /// The class of the feature.
    public var featureClass: FeatureClass
    /// The OSM ID of the way or relation.
    public var objectID: Int64
    /// The closed rings to fill with the even-odd rule (outer rings and holes).
    public var rings: [[ScreenPoint]]
    /// The runs of real (not clip-created) edges, to stroke. A ring without artificial edges comes back closed.
    public var outline: [[ScreenPoint]]
    /// The `name`, if any.
    public var name: String?
    /// Whether the area could not be assembled completely. It is drawn as an outline and not filled.
    public var isIncomplete: Bool

    /// Creates an area piece.
    public init(
        featureClass: FeatureClass, objectID: Int64, rings: [[ScreenPoint]], outline: [[ScreenPoint]],
        name: String? = nil, isIncomplete: Bool = false
    ) {
        self.featureClass = featureClass
        self.objectID = objectID
        self.rings = rings
        self.outline = outline
        self.name = name
        self.isIncomplete = isIncomplete
    }
}
