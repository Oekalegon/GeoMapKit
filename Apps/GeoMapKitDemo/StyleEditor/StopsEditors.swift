import MapStyle
import SwiftUI

/// A colour that can change with the zoom: one colour, or colours at some zooms with the colours between them blended.
struct ColorStopsEditor: View {
    let title: String
    @Binding var value: ZoomValue<MapColor>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                if value.isConstant { picker(0) }
            }
            if !value.isConstant {
                ForEach(Array(value.stops.enumerated()), id: \.offset) { index, _ in
                    HStack {
                        Stepper(value: zoom(index), in: 0...24, step: 0.5) { Text("From zoom \(zoomText(index))").font(.subheadline) }
                        picker(index)
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

    private func picker(_ index: Int) -> some View {
        ColorPicker(
            title,
            selection: Binding(
                get: { ColorConversion.color(value.stops.indices.contains(index) ? value.stops[index].value : .black) },
                set: { value = value.settingValue(ColorConversion.mapColor($0), at: index) }),
            supportsOpacity: true
        ).labelsHidden()
    }

    private func zoom(_ index: Int) -> Binding<Double> {
        Binding(
            get: { value.stops.indices.contains(index) ? value.stops[index].zoom : 0 },
            set: { value = value.settingZoom($0, at: index) })
    }

    private func zoomText(_ index: Int) -> String {
        String(format: "%g", value.stops.indices.contains(index) ? value.stops[index].zoom : 0)
    }
}

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

/// The lowest and the highest zoom at which something is shown.
struct ZoomRangeEditor: View {
    let title: String
    @Binding var range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
            Stepper(value: Binding(get: { range.lowerBound }, set: { range = min($0, range.upperBound)...range.upperBound }), in: 0...24, step: 0.5) {
                Text("From zoom \(String(format: "%g", range.lowerBound))").font(.subheadline)
            }
            Stepper(value: Binding(get: { range.upperBound }, set: { range = range.lowerBound...max($0, range.lowerBound) }), in: 0...24, step: 0.5) {
                Text("To zoom \(String(format: "%g", range.upperBound))").font(.subheadline)
            }
        }
    }
}
