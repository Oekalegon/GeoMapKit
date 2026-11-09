import FeatureStore

/// A point feature ready to draw, in screen points.
public struct ScenePoint: Sendable, Equatable {
    /// The class of the feature.
    public var featureClass: FeatureClass
    /// The OSM ID of the node.
    public var objectID: Int64
    /// The position in screen points.
    public var position: ScreenPoint
    /// The `name`, if any.
    public var name: String?
    /// The subclass byte of the feature (for a place, its rank: 1 city, 2 town, 3 village).
    public var subclass: UInt8
    /// The `population` of a place, if the feature has the tag and it reads as a number.
    public var population: Int?

    /// Creates a point.
    public init(featureClass: FeatureClass, objectID: Int64, position: ScreenPoint, name: String? = nil, subclass: UInt8 = 0, population: Int? = nil) {
        self.subclass = subclass
        self.population = population
        self.featureClass = featureClass
        self.objectID = objectID
        self.position = position
        self.name = name
    }
}
