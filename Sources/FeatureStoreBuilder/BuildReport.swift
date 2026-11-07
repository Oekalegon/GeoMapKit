import FeatureStore

/// What the builder did, and what it could not do.
public struct BuildReport: Sendable, Equatable {
    /// The number of cells fully inside the cut area, which are the cells that were written.
    public var cellsInArea = 0
    /// Tagged nodes stored as point features.
    public var nodesStored = 0
    /// Ways stored as line or area features.
    public var waysStored = 0
    /// Untagged ways left out because a multipolygon relation holds their geometry, and ways whose tags a
    /// single-outer-way multipolygon adopted.
    public var waysSuppressed = 0
    /// Ways with a node missing from the extract; they are split at the gap.
    public var waysWithMissingNodes = 0
    /// Ways with no usable geometry at all.
    public var waysWithoutGeometry = 0
    /// Relations stored in the relation table.
    public var relationsStored = 0
    /// Multipolygon relations assembled into polygons.
    public var multipolygonsAssembled = 0
    /// Multipolygon relations that could not be assembled and are stored as outlines only.
    public var multipolygonsIncomplete = 0
    /// Polygons (outer rings with holes) over all assembled multipolygons.
    public var polygons = 0
    /// Assembly problems summed over all multipolygons: chains that did not close.
    public var unclosedChains = 0
    /// Rings dropped for having no area or fewer than four points.
    public var degenerateRings = 0
    /// Inner rings that no outer ring contains.
    public var orphanInnerRings = 0
    /// Member ways of multipolygons that are missing from the extract.
    public var missingMembers = 0
    /// Features not written because the profile excludes their class.
    public var featuresSkippedByProfile = 0
    /// Pieces (detail band) that fall in cells outside the written area, and were dropped.
    public var piecesOutsideCells = 0
    /// Coastline ways found in the extract.
    public var coastlineWays = 0
    /// Sea polygons built from the coastlines.
    public var seaPolygons = 0
    /// Islands cut out of the sea.
    public var seaIslands = 0
    /// Coastline ends inside the stored area, or coastline ways with a node missing: when this is not zero no sea was
    /// built, because the side the water is on could not be followed to the border of the area.
    public var seaOpenEnds = 0
    /// The number of stored features per class (each feature counted once, not per band or piece).
    public var featuresByClass: [FeatureClass: Int] = [:]

    /// Creates an empty report; every counter starts at zero.
    public init() {}
}
