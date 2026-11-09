import MapStyle
import SwiftUI

/// The settings of the whole style: its name, the background, the credit and the spacing of names.
struct GeneralEditorView: View {
    let model: StyleEditorModel

    var body: some View {
        Form {
            Section("Style") {
                TextField("Name", text: Binding(get: { model.style.name }, set: { new in model.change("general.name") { $0.name = new } }))
                ColorPicker(
                    "Background",
                    selection: Binding(
                        get: { ColorConversion.color(model.style.background) },
                        set: { new in model.change("general.background") { $0.background = ColorConversion.mapColor(new) } }),
                    supportsOpacity: false)
                Text("The colour behind everything, where no land or water is drawn: \(ColorConversion.hex(model.style.background))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Picker("Credit", selection: Binding(get: { model.style.attribution }, set: { new in model.change("general.attribution") { $0.attribution = new } })) {
                    Text("Full").tag(AttributionDisplay.full)
                    Text("Short (© OSM)").tag(AttributionDisplay.compact)
                    Text("Hidden").tag(AttributionDisplay.hidden)
                }
            } footer: {
                Text("The data of OpenStreetMap asks for a credit; if you hide it here, show it somewhere else in the app.")
            }
            Section("Names") {
                Stepper(
                    value: Binding(get: { model.style.labels.padding }, set: { new in model.change("general.padding") { $0.labels.padding = max(new, 0) } }),
                    in: 0...20, step: 0.5
                ) { Text("Space around a name: \(String(format: "%g", model.style.labels.padding)) points") }
                Toggle("Limit the number of names", isOn: Binding(
                    get: { model.style.labels.maximumCount != nil },
                    set: { on in model.change("general.limit") { $0.labels.maximumCount = on ? ($0.labels.maximumCount ?? 100) : nil } }))
                if let limit = model.style.labels.maximumCount {
                    Stepper(
                        value: Binding(get: { limit }, set: { new in model.change("general.count") { $0.labels.maximumCount = max(new, 0) } }),
                        in: 0...2_000, step: 10
                    ) { Text("At most \(limit) names in a view") }
                }
            }
        }
        .navigationTitle("General")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
