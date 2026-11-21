#if !os(watchOS)
import SwiftUI
import TrackOverlays

/// A legend of a heat map for SwiftUI: a line in the colour and width of each step, with the counts it stands for.
///
/// It is made from ``HeatMapLegend``, so it shows the scale the overlay uses. It is for the phone and the Mac; the Watch has no heat map.
public struct HeatMapLegendView: View {
    private let legend: HeatMapLegend
    private let title: String

    /// Creates a legend view.
    ///
    /// - Parameters:
    ///   - title: What is counted, for example "Activities" or "Passes".
    ///   - legend: The steps; those of the standard scale by default.
    public init(title: String, legend: HeatMapLegend = HeatMapLegend()) {
        self.title = title
        self.legend = legend
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2.weight(.semibold))
            ForEach(Array(legend.entries.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 6) {
                    Capsule()
                        .fill(Color(.sRGB, red: entry.style.color.red, green: entry.style.color.green, blue: entry.style.color.blue, opacity: 1))
                        .frame(width: 22, height: max(entry.style.width, 2))
                        .frame(height: 6)
                    Text(entry.label).font(.caption2).monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heat map legend, \(title)")
        .accessibilityValue(legend.entries.map(\.label).joined(separator: ", "))
    }
}
#endif
