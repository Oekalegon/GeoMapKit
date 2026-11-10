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
    /// The line starts where a bridge or a tunnel starts or ends, or (for a road) at a vertex in the middle of another road,
    /// so the renderer ends it flat there: a road that comes out of a tunnel mouth, or ends at the side of another road,
    /// should not start with a round cap.
    public var flatStart: Bool
    /// The line ends where a bridge or a tunnel starts or ends, or at the side of another road; see ``flatStart``.
    public var flatEnd: Bool
    /// For a road: the width in points to blend to at the start, where another road of the same class continues it with a
    /// different lane count; `nil` for none. The renderer tapers the first stretch of the line from this width to its own.
    public var startWidth: Double?
    /// The width in points to blend to at the end; see ``startWidth``.
    public var endWidth: Double?
    /// The index of the style variant of the class this feature is drawn with (see `ClassStyle.variants`), or `nil` for the class's own look.
    public var variant: Int? = nil

    /// Creates a line.
    public init(
        featureClass: FeatureClass, objectID: Int64, points: [ScreenPoint], lanes: Int? = nil, name: String? = nil,
        structure: Structure = .ground, flatStart: Bool = false, flatEnd: Bool = false,
        startWidth: Double? = nil, endWidth: Double? = nil
    ) {
        self.startWidth = startWidth
        self.endWidth = endWidth
        self.structure = structure
        self.flatStart = flatStart
        self.flatEnd = flatEnd
        self.featureClass = featureClass
        self.objectID = objectID
        self.points = points
        self.lanes = lanes
        self.name = name
    }
}
