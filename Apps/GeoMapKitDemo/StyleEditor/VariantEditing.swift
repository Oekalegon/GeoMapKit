import FeatureStore
import MapStyle
import SwiftUI

/// A variant of a class, as a navigation value.
struct VariantRef: Hashable {
    let featureClass: FeatureClass
    let index: Int
}

extension StyleVariant {
    /// The name, or what the variant selects when it has none.
    var title: String {
        if !name.isEmpty { return name }
        let selected = subclasses + tags.map { $0.values.isEmpty ? $0.key : "\($0.key)=\($0.values.joined(separator: "|"))" }
        return selected.isEmpty ? "All the rest" : selected.joined(separator: ", ")
    }
}

/// The variants of a class, in the order that decides which one wins, with a button to add one.
struct VariantsSection: View {
    let model: StyleEditorModel
    let featureClass: FeatureClass

    private var variants: [StyleVariant] { model.style.classes[featureClass]?.variants ?? [] }

    var body: some View {
        Section {
            ForEach(Array(variants.enumerated()), id: \.offset) { index, variant in
                NavigationLink(value: VariantRef(featureClass: featureClass, index: index)) {
                    VStack(alignment: .leading) {
                        Text(variant.title)
                        Text(summary(variant)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                model.change("variant.delete") { style in
                    style.classes[featureClass]?.variants.remove(atOffsets: offsets)
                }
            }
            Button { add() } label: { Label("Add a variant", systemImage: "plus.circle") }
        } header: { Text("Variants") } footer: {
            Text("A variant gives some of the features of this class a look of their own, for example the motorways among the major roads. The first variant that matches a feature wins.")
        }
    }

    private func summary(_ variant: StyleVariant) -> String {
        var parts: [String] = []
        if variant.fill != nil { parts.append("fill") }
        if variant.stroke != nil { parts.append("line") }
        if variant.point != nil { parts.append("point") }
        if variant.label != nil { parts.append("name") }
        if variant.visibleZoom != nil || variant.layer != nil { parts.append("zoom or layer") }
        return parts.isEmpty ? "looks like the class" : "own " + parts.joined(separator: ", ")
    }

    /// A new variant for the first subclass name of the class (or for any feature, if the class has no names: select by a tag then).
    private func add() {
        let first = SubclassNames.names(of: featureClass).first
        model.change("variant.add") { style in
            style.classes[featureClass]?.variants.append(StyleVariant(name: "", subclasses: first.map { [$0] } ?? []))
        }
    }
}

/// What a variant selects: its name, the subclass names, and the tag conditions, with its place in the order.
struct VariantSelectorSection: View {
    let model: StyleEditorModel
    let featureClass: FeatureClass
    let variant: Int
    @Environment(\.dismiss) private var dismiss

    private var current: StyleVariant? {
        guard let list = model.style.classes[featureClass]?.variants, list.indices.contains(variant) else { return nil }
        return list[variant]
    }

    private func edit(_ key: String, _ body: @escaping (inout StyleVariant) -> Void) {
        let variant = variant
        model.change("variant.\(featureClass).\(variant).\(key)") { style in
            guard var list = style.classes[featureClass]?.variants, list.indices.contains(variant) else { return }
            body(&list[variant])
            style.classes[featureClass]?.variants = list
        }
    }

    var body: some View {
        if let current {
            Section("Variant") {
                TextField("Name", text: Binding(get: { current.name }, set: { new in edit("name") { $0.name = new } }))
                #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                #endif
            }
            let names = SubclassNames.names(of: featureClass)
            if !names.isEmpty {
                Section {
                    ForEach(names, id: \.self) { name in
                        Toggle(name, isOn: Binding(
                            get: { current.subclasses.contains(name) },
                            set: { on in
                                edit("subclass.\(name)") { v in
                                    if on { if !v.subclasses.contains(name) { v.subclasses.append(name) } } else { v.subclasses.removeAll { $0 == name } }
                                }
                            }))
                    }
                } header: { Text("Which kinds") } footer: {
                    Text("The features whose kind is ticked. None ticked: every kind (use the tags below to narrow it).")
                }
            }
            Section {
                ForEach(Array(current.tags.enumerated()), id: \.offset) { index, condition in
                    VStack(alignment: .leading) {
                        TextField("Tag, for example gauge", text: Binding(
                            get: { condition.key },
                            set: { new in edit("tag.\(index).key") { if $0.tags.indices.contains(index) { $0.tags[index].key = new } } }))
                        TextField("Values, separated by commas (empty: any value)", text: Binding(
                            get: { condition.values.joined(separator: ", ") },
                            set: { text in
                                edit("tag.\(index).values") {
                                    guard $0.tags.indices.contains(index) else { return }
                                    $0.tags[index].values = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                }
                            }))
                        .font(.callout)
                    }
                }
                .onDelete { offsets in edit("tag.delete") { $0.tags.remove(atOffsets: offsets) } }
                Button { edit("tag.add") { $0.tags.append(TagCondition(key: "")) } } label: { Label("Add a tag condition", systemImage: "plus.circle") }
            } header: { Text("Tags") } footer: {
                Text("All conditions must be met. Tags other than the kind are known from zoom 15; at lower zoom a tag condition does not match.")
            }
            Section("Order and removal") {
                Button("Move up") { move(by: -1) }.disabled(variant == 0)
                Button("Move down") { move(by: 1) }.disabled(variant >= (model.style.classes[featureClass]?.variants.count ?? 0) - 1)
                Button("Remove this variant", role: .destructive) {
                    model.change("variant.remove") { $0.classes[featureClass]?.variants.remove(at: variant) }
                    dismiss()
                }
            }
        }
    }

    private func move(by step: Int) {
        let from = variant
        model.change("variant.move") { style in
            guard var list = style.classes[featureClass]?.variants, list.indices.contains(from), list.indices.contains(from + step) else { return }
            list.swapAt(from, from + step)
            style.classes[featureClass]?.variants = list
        }
        dismiss()
    }
}
