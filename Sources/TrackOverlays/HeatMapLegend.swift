import MapRender

/// What the colours and widths of a heat map mean: one entry for each step of the scale.
///
/// The legend is made from the scale the overlay uses, so it cannot say something else than the map does. An app draws it as it likes;
/// `HeatMapLegendView` of the `TrackHeatMap` target is a ready one for SwiftUI.
public struct HeatMapLegend: Sendable, Equatable {
    /// One step: the counts that have this look.
    public struct Entry: Sendable, Equatable {
        /// The least count of the step.
        public let minimumCount: Int
        /// The highest count of the step, or `nil` for the last step, which has no limit.
        public let maximumCount: Int?
        /// How a line of this step looks.
        public let style: OverlayLineStyle

        /// The counts as text: "1", "2–3" or "30+".
        public var label: String {
            guard let maximumCount else { return "\(minimumCount)+" }
            return maximumCount == minimumCount ? "\(minimumCount)" : "\(minimumCount)–\(maximumCount)"
        }
    }

    /// The steps from the lowest count to the highest.
    public let entries: [Entry]

    /// The legend of a scale.
    ///
    /// - Parameter scale: The scale of the overlay; ``HeatMapScale/standard`` by default.
    public init(scale: HeatMapScale = .standard) {
        entries = scale.steps.enumerated().map { index, step in
            let next = index + 1 < scale.steps.count ? scale.steps[index + 1].minimumCount - 1 : nil
            return Entry(minimumCount: step.minimumCount, maximumCount: next, style: step.style)
        }
    }
}
