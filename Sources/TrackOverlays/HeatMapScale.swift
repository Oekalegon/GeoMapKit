import MapRender
import MapStyle

/// The colours and widths of a heat map by count: a fixed scale, so that two maps (two months of a time-lapse, road and trail) are
/// drawn with the same meaning for a colour.
///
/// The width carries the same information as the colour (a busier bucket is wider), so the map can be read without telling the colours
/// apart. A scale in one hue is for later, with a style that can choose it.
public struct HeatMapScale: Sendable, Equatable {
    /// One step of the scale: from a count up, until the next step.
    public struct Step: Sendable, Equatable {
        /// The least count that has this look.
        public var minimumCount: Int
        /// How the line looks.
        public var style: OverlayLineStyle

        /// Creates a step.
        public init(minimumCount: Int, style: OverlayLineStyle) {
            self.minimumCount = minimumCount
            self.style = style
        }
    }

    /// The steps from the least count to the highest, in order of `minimumCount`, at least one.
    public let steps: [Step]

    /// Creates a scale. The steps are put in order of their least count.
    ///
    /// - Parameter steps: At least one step.
    /// - Returns: `nil` for no steps, which is not a scale.
    public init?(steps: [Step]) {
        guard !steps.isEmpty else { return nil }
        self.steps = steps.sorted { $0.minimumCount < $1.minimumCount }
    }

    /// The index of the step for a count, or `nil` for a count below the first step.
    func stepIndex(for count: Int) -> Int? {
        var found: Int?
        for (index, step) in steps.enumerated() where count >= step.minimumCount { found = index }
        return found
    }

    /// Yellow for a bucket used once to dark red for 30 or more, thin to wide, counts of 1, 2 to 3, 4 to 9, 10 to 29 and 30 and more.
    public static let standard = HeatMapScale(rawSteps: [
        Step(minimumCount: 1, style: OverlayLineStyle(color: MapColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 0.8), width: 2.5)),
        Step(minimumCount: 2, style: OverlayLineStyle(color: MapColor(red: 1.0, green: 0.62, blue: 0.1, alpha: 0.85), width: 3.0)),
        Step(minimumCount: 4, style: OverlayLineStyle(color: MapColor(red: 0.95, green: 0.38, blue: 0.1, alpha: 0.9), width: 3.5)),
        Step(minimumCount: 10, style: OverlayLineStyle(color: MapColor(red: 0.8, green: 0.12, blue: 0.1, alpha: 0.92), width: 4.5)),
        Step(minimumCount: 30, style: OverlayLineStyle(color: MapColor(red: 0.5, green: 0.0, blue: 0.1, alpha: 0.95), width: 5.5)),
    ])

    private init(rawSteps: [Step]) { steps = rawSteps }
}
