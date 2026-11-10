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
    /// Ways with no class of their own that took the class of a national or state border from a border relation they belong to.
    public var waysTakingBorderFromRelation = 0
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
    /// Rings (buildings, small areas) that simplification for the mid band reduced to less than a polygon, and so are
    /// missing from that band (they are still in the detail band).
    public var ringsTooSmallForMid = 0
    /// Pieces (detail band) that fall in cells outside the written area, and were dropped.
    public var piecesOutsideCells = 0
    /// Footways that were classed as pavement because they run beside a road, without a sidewalk tag of their own counted.
    public var footwaysBesideRoads = 0
    /// Footways that were classed as pavement because they lie in a built-up area (a plaza, a yard, a car park, a station).
    public var footwaysInTown = 0
    /// Built-up areas that the footway test used (closed ways and multipolygon relations); 0 if no footway needed the test.
    public var townAreas = 0
    /// Green areas that the footway test used.
    public var greenAreas = 0
    /// Coastline ways found in the extract.
    public var coastlineWays = 0
    /// Coastline ways left out because a node is missing from the extract.
    public var coastlineWaysSkipped = 0
    /// Gaps in the coastlines closed with a straight line (where the extract stops at a country border, or a way is broken).
    public var seaGapsClosed = 0
    /// Loose coastline ends at a country border that were carried straight on to the edge of the area.
    public var seaEndsExtended = 0
    /// The longest of those gaps, in metres.
    public var seaLongestGap = 0.0
    /// Sea polygons built from the coastlines.
    public var seaPolygons = 0
    /// Islands cut out of the sea.
    public var seaIslands = 0
    /// Coastline ends inside the stored area, or coastline ways with a node missing: when this is not zero no sea was
    /// built, because the side the water is on could not be followed to the border of the area.
    public var seaOpenEnds = 0
    /// Stretches of coastline left out because they run through the water of a river (they close its mouth).
    public var coastlineStretchesInRivers = 0
    /// Stretches of a named river's centre line in the river's own area that were kept as `riverName` lines, for the name.
    public var riverNameStretches = 0
    /// Stretches of a river's centre line left out because they lie in the river's own area.
    public var waterLineStretchesInWater = 0
    /// The stretches of rivers and streams in a thin or small water area: lines in the overview band only, names from the mid band.
    public var waterLineStretchesInThinWater = 0
    /// Ways stored a second time as an overlay class: a border that is also a stream, a reserve that is also a forest, a piste on a track.
    public var overlayFeatures = 0
    /// Stretches of the border of protected areas that lie in the sea.
    public var parkBorderStretchesInSea = 0
    /// The number of stored features per class (each feature counted once, not per band or piece).
    public var featuresByClass: [FeatureClass: Int] = [:]

    /// Creates an empty report; every counter starts at zero.
    public init() {}
}
