/// The derived feature classes of the v1 map.
///
/// A class is derived data: it drives styling, default visibility and the Watch
/// profile, and never replaces the raw tags, which stay in the store. The raw
/// values are stored in the file, so they are stable; new classes are appended.
public enum FeatureClass: UInt8, CaseIterable, Sendable {
    /// Anything the classifier does not recognize. The tags are kept.
    case other = 0
    /// Footpaths, bridleways, cycleways, steps and via ferratas.
    case path = 1
    /// Tracks (`highway=track`); the subclass is the `tracktype` grade.
    case track = 2
    /// Motorways down to tertiary roads.
    case roadMajor = 3
    /// Unclassified, residential, service and similar roads.
    case roadMinor = 4
    /// Railways.
    case railway = 5
    /// Rivers, canals, streams, ditches and drains.
    case waterLine = 6
    /// Lakes, ponds, reservoirs and river banks.
    case waterArea = 7
    /// Woodland.
    case forest = 8
    /// Natural and cultivated land cover (heath, meadow, farmland, parks and so on).
    case landcover = 9
    /// Urban land use (residential, industrial, commercial and so on).
    case landuseUrban = 10
    /// Buildings.
    case building = 11
    /// Peaks, volcanoes and saddles.
    case peak = 12
    /// Cities, towns, villages and smaller places.
    case place = 13
    /// Points of interest a runner navigates by: water, springs, huts, shelters.
    case poiAnchor = 14
    /// Other points of interest (amenities, shops, tourism, historic and so on).
    case poi = 15
    /// Administrative and protected-area boundaries.
    case boundary = 16
}
