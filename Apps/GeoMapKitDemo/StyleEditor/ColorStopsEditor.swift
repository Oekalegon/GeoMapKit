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
