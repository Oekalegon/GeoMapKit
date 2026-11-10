import FeatureStore
import MapStyle
import SwiftUI

/// The classes of the style in groups: tap one to change it.
struct ClassListView: View {
    let model: StyleEditorModel
    @State private var search = ""

    var body: some View {
        List {
            ForEach(ClassGroups.groups) { group in
                let shown = group.classes.filter { search.isEmpty || ClassGroups.name(of: $0).localizedCaseInsensitiveContains(search) }
                if !shown.isEmpty {
                    Section(group.title) {
                        ForEach(shown, id: \.self) { featureClass in
                            NavigationLink(value: featureClass) { row(featureClass) }
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Find a class")
        .navigationDestination(for: FeatureClass.self) { ClassEditorView(model: model, featureClass: $0) }
        .navigationDestination(for: VariantRef.self) { ClassEditorView(model: model, featureClass: $0.featureClass, variant: $0.index) }
        .navigationTitle("Classes")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func row(_ featureClass: FeatureClass) -> some View {
        let style = model.style.classes[featureClass]
        return HStack {
            swatch(style)
            VStack(alignment: .leading) {
                Text(ClassGroups.name(of: featureClass))
                Text(detail(style)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func swatch(_ style: ClassStyle?) -> some View {
        let fill = style?.fill?.color.value(atZoom: 14)
        let line = style?.stroke?.color.value(atZoom: 14)
        RoundedRectangle(cornerRadius: 4)
            .fill(fill.map(ColorConversion.color) ?? Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(line.map(ColorConversion.color) ?? Color.secondary.opacity(0.4), lineWidth: line == nil ? 1 : 2))
            .frame(width: 26, height: 18)
    }

    private func detail(_ style: ClassStyle?) -> String {
        guard let style else { return "Not drawn" }
        var parts: [String] = []
        if style.fill != nil { parts.append("fill") }
        if style.stroke != nil { parts.append("line") }
        if style.point != nil { parts.append("point") }
        if style.label != nil { parts.append("name") }
        let kinds = parts.isEmpty ? "nothing" : parts.joined(separator: ", ")
        return "\(kinds) · zoom \(String(format: "%g", style.visibleZoom.lowerBound))–\(String(format: "%g", style.visibleZoom.upperBound)) · layer \(style.layer)"
    }
}
