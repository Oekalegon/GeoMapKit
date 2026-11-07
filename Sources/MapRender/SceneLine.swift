import FeatureStore
import MapStyle

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
    /// Whether the line is on the ground, a bridge or a tunnel, as the subclass byte of the feature says.
    public var structure: Structure

    /// Creates a line.
    public init(
        featureClass: FeatureClass, objectID: Int64, points: [ScreenPoint], lanes: Int? = nil, name: String? = nil,
        structure: Structure = .ground
    ) {
        self.structure = structure
        self.featureClass = featureClass
        self.objectID = objectID
        self.points = points
        self.lanes = lanes
        self.name = name
    }
}
