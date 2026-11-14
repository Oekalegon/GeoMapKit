import FeatureStore
import MapStyle

/// Everything to draw for one viewport: a list of steps in drawing order, in screen points.
///
/// A scene has no graphics dependency. It is built once per change of position or zoom and any backend can draw
/// it, and tests can check it without a graphics context.
public struct MapScene: Sendable, Equatable {
    /// The viewport the scene was built for.
    public var viewport: MapViewport
    /// The band that was read from the file.
    public var band: ZoomBand
    /// The steps in drawing order. Steps without features are left out.
    public var steps: [SceneStep]
    /// The number of store cells that were read.
    public var cellCount: Int
    /// What the overlays draw over the features, before the labels: items in screen points (see ``MapOverlay``).
    public var overlays: [OverlayItem]
    /// The data credit of the store file (for OpenStreetMap data, the ODbL notice). A backend draws it in a corner
    /// of the map; it must not be dropped from anything derived from OSM data.
    public var attribution: String

    /// Creates a scene from its parts.
    public init(
        viewport: MapViewport, band: ZoomBand, steps: [SceneStep], cellCount: Int, attribution: String = "", overlays: [OverlayItem] = []
    ) {
        self.viewport = viewport
        self.band = band
        self.steps = steps
        self.cellCount = cellCount
        self.attribution = attribution
        self.overlays = overlays
    }
}
