/// One piece of a feature in one cell and one band.
///
/// A feature that crosses cell borders is stored as one piece per cell, all with
/// the same ``objectType`` and ``objectID``.
public struct StoredFeature: Hashable, Sendable {
    /// The derived feature class. The class table belongs to the builder; the file only stores the number.
    public var classID: UInt8
    /// The derived subclass (for example the `highway` value), 0 if unused.
    public var subclass: UInt8
    public var kind: FeatureKind
    public var objectType: StoredObjectType
    /// The OSM ID of the way, node or relation.
    public var objectID: Int64
    public var flags: FeatureFlags
    /// The distance along the original line to the start of this piece, in centimetres.
    public var offsetAlongLine: UInt32
    /// String ID of the `name` value, for labels in every band.
    public var nameID: UInt32?
    /// The tags, as string IDs, written as given in every band. The builder gives all tags in the detail band and none in the others,
    /// except for a `landUse` feature, which carries the value of its `landuse` or `natural` tag in every band.
    public var tags: [StoredTag]
    public var parts: [GeometryPart]

    public init(
        classID: UInt8, subclass: UInt8 = 0, kind: FeatureKind, objectType: StoredObjectType,
        objectID: Int64, flags: FeatureFlags = [], offsetAlongLine: UInt32 = 0, nameID: UInt32? = nil,
        tags: [StoredTag] = [], parts: [GeometryPart]
    ) {
        self.classID = classID
        self.subclass = subclass
        self.kind = kind
        self.objectType = objectType
        self.objectID = objectID
        self.flags = flags
        self.offsetAlongLine = offsetAlongLine
        self.nameID = nameID
        self.tags = tags
        self.parts = parts
    }
}
