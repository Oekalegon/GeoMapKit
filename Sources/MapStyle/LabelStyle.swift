/// How the `name` of a feature is labelled.
public struct LabelStyle: Sendable, Equatable {
    /// The font size in points.
    public var size: ZoomValue<Double>
    /// The text colour.
    public var color: MapColor
    /// The colour of the outline that keeps the text legible on any background.
    public var haloColor: MapColor
    /// The halo width in points, 0 for none.
    public var haloWidth: Double
    /// Higher priority labels are placed first and win a collision.
    public var priority: Int
    /// The zoom range in which this label is shown. It can be narrower than the class's own `visibleZoom`, so a
    /// name appears later than its shape.
    public var visibleZoom: ClosedRange<Double>
    /// For the name of a line: on the line, or beside it. Names of points and areas ignore it.
    public var placement: LabelPlacement
    /// The smallest area, in square points on the screen, that an area must cover to get this label: a pond is not named, a lake is.
    /// It only applies to areas; 0 names every area.
    public var minimumArea: Double
    /// For the name of a point: within this many points of a larger place of the same class, a place gets no name (the larger is
    /// the lower subclass number, then the greater `population`). 0 for no thinning. By zoom, so it can fade out.
    public var thinningRadius: ZoomValue<Double>
    /// For the name of a place: the part of ``thinningRadius`` that applies to a city (subclass 1), 1 or less and more than 0. A city is
    /// hidden only by another city within this shorter distance, so two real cities near each other (Haarlem and Amsterdam) are both named,
    /// while a town or village is hidden by any larger place within the full radius. 1 treats a city like every other place.
    public var cityThinningFactor: Double
    /// For the name of a place: the font size follows the population, see ``PopulationScale``. `nil` writes every name at `size`.
    public var populationScale: PopulationScale?

    /// Creates a label style.
    public init(
        size: ZoomValue<Double>, color: MapColor, haloColor: MapColor = .white, haloWidth: Double = 2,
        priority: Int = 0,
        visibleZoom: ClosedRange<Double> = 0...24,
        placement: LabelPlacement = .onLine,
        minimumArea: Double = 0,
        thinningRadius: ZoomValue<Double> = ZoomValue(constant: 0),
        cityThinningFactor: Double = 1,
        populationScale: PopulationScale? = nil
    ) {
        self.thinningRadius = thinningRadius
        self.cityThinningFactor = min(max(cityThinningFactor, 0.01), 1)
        self.populationScale = populationScale
        self.size = size
        self.color = color
        self.haloColor = haloColor
        self.haloWidth = haloWidth
        self.priority = priority
        self.visibleZoom = visibleZoom
        self.placement = placement
        self.minimumArea = minimumArea
    }
}
