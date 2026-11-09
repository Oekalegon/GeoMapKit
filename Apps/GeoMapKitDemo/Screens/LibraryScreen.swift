import FeatureStore
import MapStyle
import SwiftUI
import UniformTypeIdentifiers

/// The maps and styles the user has stored: pick one, add, rename, delete, share.
struct LibraryScreen: View {
    @Environment(MapLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    private enum ImportKind: Identifiable {
        case maps, styles
        var id: Self { self }
    }

    private enum Renaming: Identifiable {
        case map(MapItem), style(StyleItem)
        var id: String {
            switch self {
            case .map(let item): "map:\(item.id)"
            case .style(let item): "style:\(item.id)"
            }
        }
        var name: String {
            switch self {
            case .map(let item): item.name
            case .style(let item): item.name
            }
        }
    }

    @State private var importing: ImportKind?
    @State private var errors: [LibraryError] = []
    @State private var renaming: Renaming?
    @State private var newName = ""

    /// The type of a `.gmk` file, declared by the app (see the project's `Info.plist`).
    static let storeType = UTType(exportedAs: "org.oekalegon.geomapkit.store", conformingTo: .data)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if library.maps.isEmpty {
                        Text("No maps. Add a feature store (.gmk) from the Files app, or a folder of blocks (a manifest.json and its block files).")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(library.maps) { map in mapRow(map) }
                } header: { Text("Maps") }

                Section {
                    styleRow("Standard", choice: .standard)
                    styleRow("Watch", choice: .watch)
                    ForEach(library.styles) { style in styleRow(style.name, choice: .user(style.id), item: style) }
                } header: { Text("Styles") } footer: {
                    Text("A style is chosen for the map that is open. Touch and hold a style to make a copy of it that you can change.")
                }
            }
            .navigationTitle("Library")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { importing = .maps } label: { Label("Add a map…", systemImage: "map") }
                        Button { importing = .styles } label: { Label("Add a style…", systemImage: "paintpalette") }
                    } label: { Label("Add", systemImage: "plus") }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileImporter(
                isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }),
                allowedContentTypes: importing == .styles ? [.json] : [.folder, Self.storeType], allowsMultipleSelection: true
            ) { result in
                guard case .success(let urls) = result else { return }
                let added = library.add(urls)
                errors = added.errors
                // What was just added is what the user wants: a map is opened, a style is applied to the map that is open.
                if let id = added.maps.first {
                    library.selectedMapID = id
                } else if let id = added.styles.first, let map = library.selectedMapID {
                    library.setStyleChoice(.user(id), forMap: map)
                }
            }
            .alert("Could not add", isPresented: Binding(get: { !errors.isEmpty }, set: { if !$0 { errors = [] } })) {
                Button("OK") { errors = [] }
            } message: {
                Text(errors.compactMap(\.errorDescription).joined(separator: "\n"))
            }
            .alert(
                "Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
            ) {
                TextField("Name", text: $newName)
                Button("Rename") { rename() }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    // MARK: Rows

    private func mapRow(_ map: MapItem) -> some View {
        Button {
            library.selectedMapID = map.id
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(map.name)
                    Text(detail(of: map)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if library.selectedMapID == map.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { begin(.map(map)) } label: { Label("Rename…", systemImage: "pencil") }
            if map.kind == .file { ShareLink(item: library.url(of: map)) }
            Button(role: .destructive) { remove(map) } label: { Label("Remove", systemImage: "trash") }
        }
        .swipeActions {
            Button(role: .destructive) { remove(map) } label: { Label("Remove", systemImage: "trash") }
        }
    }

    private func detail(of map: MapItem) -> String {
        switch map.kind {
        case .file: map.bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
        case .blocks: "A folder of blocks, where it is"
        case .linkedFile: "A big file, where it is"
        }
    }

    @ViewBuilder private func styleRow(_ name: String, choice: StyleChoice, item: StyleItem? = nil) -> some View {
        let selectedMap = library.selectedMapID
        Button {
            if let selectedMap { library.setStyleChoice(choice, forMap: selectedMap) }
        } label: {
            HStack {
                Text(name)
                Spacer()
                if selectedMap != nil, library.styleChoice(forMap: selectedMap) == choice { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
        .buttonStyle(.plain)
        .disabled(selectedMap == nil)
        .contextMenu {
            Button { copy(choice, named: name) } label: { Label("Make a copy to edit", systemImage: "doc.on.doc") }
            if let item {
                Button { begin(.style(item)) } label: { Label("Rename…", systemImage: "pencil") }
                ShareLink(item: library.url(of: item))
                Button(role: .destructive) { remove(item) } label: { Label("Remove", systemImage: "trash") }
            }
        }
        .swipeActions {
            if let item { Button(role: .destructive) { remove(item) } label: { Label("Remove", systemImage: "trash") } }
        }
    }

    // MARK: Actions

    private func begin(_ item: Renaming) {
        newName = item.name
        renaming = item
    }

    private func rename() {
        guard let renaming else { return }
        do {
            switch renaming {
            case .map(let item): try library.rename(item, to: newName)
            case .style(let item): try library.rename(item, to: newName)
            }
        } catch {
            errors = [(error as? LibraryError) ?? .failed(renaming.name, error.localizedDescription)]
        }
        self.renaming = nil
    }

    private func copy(_ choice: StyleChoice, named name: String) {
        do {
            let style = try library.style(for: choice)
            try library.addStyle(style, named: "\(name) copy")
        } catch {
            errors = [(error as? LibraryError) ?? .failed(name, error.localizedDescription)]
        }
    }

    private func remove(_ map: MapItem) {
        do { try library.delete(map) } catch { errors = [.failed(map.name, error.localizedDescription)] }
    }

    private func remove(_ style: StyleItem) {
        do { try library.delete(style) } catch { errors = [.failed(style.name, error.localizedDescription)] }
    }
}
