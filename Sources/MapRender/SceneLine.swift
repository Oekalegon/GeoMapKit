import FeatureStore

/// A line ready to draw, in screen points.
///
/// The pieces of one OSM way that the store cut at cell borders are joined back into one line, so joins, caps and
/// dash patterns run on across cell borders.
public struct SceneLine: Sendable, Equatable {
    /// The class of the feature.
    public var featureClass: FeatureClass
    /// The OSM ID of the way or relation.
    public var objectID: Int64
    /// The vertices in screen points, in the direction of the original line.
    public var points: [ScreenPoint]
    /// The `lanes` tag as an integer, or `nil` if the feature has none, it does not parse, or the band holds no tags.
    public var lanes: Int?
    /// The `name`, if any.
    public var name: String?

    /// Creates a line.
    public init(featureClass: FeatureClass, objectID: Int64, points: [ScreenPoint], lanes: Int? = nil, name: String? = nil) {
        self.featureClass = featureClass
        self.objectID = objectID
        self.points = points
        self.lanes = lanes
        self.name = name
    }
}
