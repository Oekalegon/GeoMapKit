import MapStyle
import SwiftUI

/// A number that can change with the zoom (a width, a size, a radius).
struct NumberStopsEditor: View {
    let title: String
    @Binding var value: ZoomValue<Double>
    var range: ClosedRange<Double> = 0...50
    var step: Double = 0.1
    var format = "%.1f"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if value.isConstant {
                Stepper(value: number(0), in: range, step: step) { Text("\(title): \(text(0))") }
            } else {
                Text(title)
                ForEach(Array(value.stops.enumerated()), id: \.offset) { index, _ in
                    HStack {
                        Stepper(value: zoom(index), in: 0...24, step: 0.5) { Text("From zoom \(String(format: "%g", zoomValue(index)))").font(.subheadline) }
                        Stepper(value: number(index), in: range, step: step) { Text(text(index)).monospacedDigit().font(.subheadline) }
                        Button { value = value.removingStop(at: index) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).accessibilityLabel("Remove this stop")
                    }
                }
            }
            HStack {
                if value.isConstant {
                    Button("Change with the zoom") { value = value.addingStop() }
                } else {
                    Button("Add a stop") { value = value.addingStop() }
                    Spacer()
                    Button("Same at every zoom") { value = value.asConstant() }
                }
            }
            .font(.footnote).buttonStyle(.borderless)
        }
    }

    private func number(_ index: Int) -> Binding<Double> {
        Binding(
            get: { value.stops.indices.contains(index) ? value.stops[index].value : 0 },
            set: { value = value.settingValue(min(max($0, range.lowerBound), range.upperBound), at: index) })
    }

    private func zoom(_ index: Int) -> Binding<Double> {
        Binding(get: { zoomValue(index) }, set: { value = value.settingZoom($0, at: index) })
    }

    private func zoomValue(_ index: Int) -> Double { value.stops.indices.contains(index) ? value.stops[index].zoom : 0 }

    private func text(_ index: Int) -> String {
        String(format: format, value.stops.indices.contains(index) ? value.stops[index].value : 0)
    }
}
