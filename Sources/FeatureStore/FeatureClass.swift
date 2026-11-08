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
    /// Power lines and pylons (towers): landmarks in open terrain. Added in rule table version 2.
    case powerLine = 17
    /// Ski pistes and other `piste:type` ways. Added in rule table version 2.
    case piste = 18
    /// Cable cars, gondolas, lifts and their stations. Added in rule table version 2.
    case aerialway = 19
    /// Individual trees and tree rows. Added in rule table version 2.
    case tree = 20
    /// Fences, walls, gates, hedges and other barriers. Added in rule table version 2.
    case barrier = 21
    /// Bus stops, public transport stops and platforms, railway stations. Added in rule table version 2.
    case transportStop = 22
    /// Road details at a point: crossings, traffic signals, street lamps and similar; from version 4 also rail crossings, switches, signals and traffic calming. Added in rule table version 2.
    case roadPoint = 23
    /// National borders (`boundary=administrative` with `admin_level=2`). Added in rule table version 3.
    case countryBorder = 24
    /// Objects that carry only address tags (`addr:*`): house numbers on a node or a bare outline. Not drawn; kept for search. Added in rule table version 4.
    case address = 25
    /// Sidewalks and road crossings for pedestrians (`highway=footway` with `footway=sidewalk`, `crossing`, `traffic_island` or `access_aisle`): the pavement of a town, apart from the paths a runner chooses. Added in rule table version 4.
    case pavement = 26
    /// Cliffs (`natural=cliff`). Added in rule table version 4.
    case cliff = 27
    /// The sea: a polygon the builder makes from the coastlines, with the islands as holes. Added in rule table version 5.
    case sea = 28
    /// A coastline (`natural=coastline`), land on the left. Added in rule table version 5.
    case coastline = 29
    /// A road, track or path that is an area: a yard, a pedestrian square, a parking aisle drawn as a polygon (`area=yes` with a `highway` tag). Added in rule table version 7.
    case roadArea = 30
    /// Service roads (`highway=service`): driveways, parking aisles, ways through a yard. Runnable like any street, but drawn finer than the streets. Added in rule table version 11.
    case roadService = 31
}
