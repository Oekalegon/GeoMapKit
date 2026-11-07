import GeoCore

/// What the `render` command should draw.
public struct RenderRequest: Equatable, Sendable {
    /// Which built-in style to use.
    public enum Style: String, Equatable, Sendable, CaseIterable {
        /// The iOS and macOS style.
        case standard
        /// The reduced Watch style.
        case watch
    }

    /// The map centre.
    public var center: Coordinate
    /// The fractional zoom level.
    public var zoom: Double
    /// The image width in points.
    public var width: Int
    /// The image height in points.
    public var height: Int
    /// Pixels per point.
    public var scale: Double
    /// How the data credit is shown. `nil` keeps the style's own choice.
    public enum Attribution: String, Equatable, Sendable, CaseIterable {
        /// The complete credit.
        case full
        /// A short "© OSM" mark.
        case compact
        /// No credit on the map; the app must show it elsewhere.
        case none
    }

    /// The style.
    public var style: Style
    /// The credit display chosen on the command line, or `nil` for the style's default.
    public var attribution: Attribution?
    /// The PNG path.
    public var output: String

    /// Creates a request.
    public init(center: Coordinate, zoom: Double, width: Int, height: Int, scale: Double, style: Style, output: String,
        attribution: Attribution? = nil
    ) {
        self.center = center
        self.zoom = zoom
        self.width = width
        self.height = height
        self.scale = scale
        self.style = style
        self.output = output
        self.attribution = attribution
    }
}
