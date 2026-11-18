#if os(macOS)
import MapBuilder
import SwiftUI

/// Puts several maps of the library in one map: tick the maps, say whether the result is a new map or is added to one of them, and start
/// (question 65, step 2). The maps are copied as they are; where two maps have a block for the same tile, the larger block is kept.
struct MergeMapsScreen: View {
    @Environment(MapLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    /// The folder of the source files and the region list, for the sea between the maps.
    let cacheDirectory: URL

    @State private var selection = Set<String>()
    /// The id of the map that the others are added to, or `nil` for a new map.
    @State private var addTo: String?
    @State private var name = "Merged map"
    @State private var model: MapMergeModel?
    @State private var problem: String?

    /// The maps that are folders of blocks: the others (a single file) cannot be merged.
    private var candidates: [MapItem] { library.maps.filter { $0.kind == .blocks } }
    private var chosen: [MapItem] { candidates.filter { selection.contains($0.id) } }
    private var canStart: Bool {
        chosen.count >= 2 && (addTo != nil || !name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let model { progress(model) } else { form }
            Divider()
            buttons.padding(12)
        }
        .frame(minWidth: 520, minHeight: 440)
        .interactiveDismissDisabled(model?.isRunning == true)
        .alert("Merge maps", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") { problem = nil }
        } message: { Text(problem ?? "") }
    }

    // MARK: Form

    private var form: some View {
        Form {
            Section("Maps") {
                if candidates.isEmpty {
                    Text("There are no maps made of blocks in the library.").foregroundStyle(.secondary)
                }
                ForEach(candidates) { map in
                    Toggle(map.name, isOn: Binding(
                        get: { selection.contains(map.id) },
                        set: { on in
                            if on { selection.insert(map.id) } else { selection.remove(map.id); if addTo == map.id { addTo = nil } }
                        }))
                }
            }
            Section("Result") {
                Picker("Put the blocks in", selection: $addTo) {
                    Text("A new map").tag(String?.none)
                    ForEach(chosen) { Text("Add to \($0.name)").tag(String?.some($0.id)) }
                }
                if addTo == nil { TextField("Name", text: $name) }
            }
            Section {
                Text("The blocks are copied as they are (on this Mac with almost no extra space). Where two maps have a block for the same tile, the larger one is kept, so a tile on a border can miss the other side. The sea between the maps is filled, and the levels are built for what changed; the second can take long for a large map.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Progress

    private func progress(_ model: MapMergeModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title(model.stage)).font(.headline)
            if model.isRunning {
                if let fraction = model.fraction { ProgressView(value: fraction) } else { ProgressView() }
                if let detail = detail(model) { Text(detail).font(.footnote).foregroundStyle(.secondary) }
            }
            if let report = model.report {
                Text("\(report.blocks) blocks, \(report.written) copied\(report.overlaps.isEmpty ? "" : ", \(report.overlaps.count) tiles in more than one map (the larger block was kept)").")
                    .font(.footnote)
            }
            ForEach(model.notes, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
            if case .failed(let message) = model.stage { Text(message).foregroundStyle(.red) }
            Spacer()
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func title(_ stage: MapMergeModel.Stage) -> String {
        switch stage {
        case .idle: "Ready"
        case .merging: "Copying the blocks…"
        case .fillingSea: "Filling the sea between the maps…"
        case .buildingLevels: "Building the levels…"
        case .registering: "Adding the map to the library…"
        case .done(_, let name): "\(name) is ready."
        case .cancelled: "Stopped. What was copied and built is kept; Continue goes on."
        case .failed: "The merge stopped."
        }
    }

    private func detail(_ model: MapMergeModel) -> String? {
        switch model.stage {
        case .merging: model.toWrite > 0 ? "\(model.written) of \(model.toWrite) blocks" : nil
        case .buildingLevels: model.levels.map { "\($0.finished) of \($0.total) level blocks" }
        default: nil
        }
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack {
            if let model {
                switch model.stage {
                case .cancelled, .failed:
                    Button("Continue") { model.start() }
                    Button("Close") { dismiss() }
                case .done:
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                default:
                    Button("Cancel") { model.cancel() }.disabled(!model.isRunning)
                }
            } else {
                Button("Close") { dismiss() }
                Spacer()
                Button("Merge") { begin() }.disabled(!canStart).keyboardShortcut(.defaultAction)
            }
        }
    }

    private func begin() {
        var inputs: [MapMergeModel.Input] = []
        for map in chosen {
            guard let folder = library.linkedFolder(of: map) else { problem = "The link of \(map.name) cannot be resolved."; return }
            inputs.append(.init(name: map.name, folder: folder))
        }
        let output: MapMergeModel.Output
        if let id = addTo, let target = chosen.first(where: { $0.id == id }), let folder = library.linkedFolder(of: target) {
            // The map that is added to is the first of the maps.
            if let at = inputs.firstIndex(where: { $0.folder == folder }) { inputs.swapAt(0, at) }
            output = .init(folder: folder, name: target.name)
        } else if let root = library.builtMapsRoot {
            let wanted = name.trimmingCharacters(in: .whitespaces)
            output = .init(folder: MapMergeModel.newFolder(named: wanted, in: root), name: wanted)
        } else {
            problem = "The folder for new maps is not known."
            return
        }
        let library = library
        let merge = MapMergeModel(inputs: inputs, output: output, tools: .live(cacheDirectory: cacheDirectory)) { folder, name in
            try library.addBuilt(folder: folder, name: name)
        }
        model = merge
        merge.start()
    }
}
#endif
