import FeatureStore
import MapStyle
import Regions
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// The maps and styles the user has stored: pick one, add, rename, delete, share.
struct LibraryScreen: View {
    @Environment(WatchLink.self) private var watch
    @Environment(MapLibrary.self) private var library
    @Environment(StyleSync.self) private var sync
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
    #if os(macOS)
    @State private var picker: RegionPickerModel?
    @State private var pickerProblem: String?
    #endif

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

                #if os(iOS)
                Section {
                    Label(watch.status.sentence, systemImage: watch.status == .ready ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                    if watch.pending > 0 { Label("\(watch.pending) on the way", systemImage: "arrow.up.circle") }
                    if let problem = watch.lastProblem { Text(problem).font(.footnote).foregroundStyle(.red) }
                } header: { Text("Apple Watch") } footer: {
                    Text("Touch and hold a map to send it to the Watch. A map for the Watch is made with Cut for the Watch on the map.")
                }
                #endif

                Section {
                    styleRow("Standard", choice: .standard)
                    styleRow("Watch", choice: .watch)
                    ForEach(library.styles) { style in styleRow(style.name, choice: .user(style.id), item: style) }
                } header: { Text("Styles") } footer: {
                    Text("A style is chosen for the map that is open. Touch and hold a style to change it (a built-in style is copied first).")
                }

                Section {
                    Toggle("Keep styles in iCloud", isOn: Binding(get: { sync.isEnabled }, set: { sync.isEnabled = $0 }))
                    Text(sync.status.sentence).font(.footnote).foregroundStyle(.secondary)
                    if let migration = sync.migration, !migration.copied.isEmpty {
                        Text("\(migration.copied.count) style\(migration.copied.count == 1 ? "" : "s") from this device were copied to iCloud; the copies here stay as a backup.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } header: { Text("iCloud") } footer: {
                    Text("The styles are shared with your other devices that use this app and the same Apple ID. Maps stay on the device.")
                }
            }
            .navigationTitle("Library")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { startImport(.maps) } label: { Label("Add a map…", systemImage: "map") }
                        Button { startImport(.styles) } label: { Label("Add a style…", systemImage: "paintpalette") }
                    } label: { Label("Add", systemImage: "plus") }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileImporter(
                isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }),
                allowedContentTypes: importing == .styles ? [.json] : [.folder, Self.storeType], allowsMultipleSelection: true
            ) { result in
                guard case .success(let urls) = result else { return }
                finishImport(urls)
            }
            #endif
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
        // A sheet on the Mac shows no toolbar, so the buttons are in the sheet itself.
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { startImport(.maps) } label: { Label("Add a map…", systemImage: "map") }
                Button { startImport(.styles) } label: { Label("Add a style…", systemImage: "paintpalette") }
                Button { openPicker() } label: { Label("Get maps…", systemImage: "arrow.down.circle") }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
            .background(.bar)
        }
        .sheet(item: $picker) { RegionPickerScreen(model: $0) }
        .alert("Get maps", isPresented: Binding(get: { pickerProblem != nil }, set: { if !$0 { pickerProblem = nil } })) {
            Button("OK") { pickerProblem = nil }
        } message: { Text(pickerProblem ?? "") }
        #endif
    }

    #if os(macOS)
    /// The picker for regions: the Geofabrik list and the source files go to the cache folder of the app.
    private func openPicker() {
        do {
            picker = try Self.makePicker()
        } catch {
            pickerProblem = "The folder for the source files cannot be used: \(error)"
        }
    }

    private static func makePicker() throws -> RegionPickerModel {
        let directory = try SourceCache.defaultDirectory()
        let downloader = URLSessionDownloader(userAgent: "GeoMapKitDemo")
        return RegionPickerModel(
            catalog: GeofabrikCatalog(directory: directory, downloader: downloader), downloader: downloader,
            cache: SourceCache(directory: directory))
    }
    #endif

    // MARK: Adding

    /// Asks for the files to add. On the Mac this is an open panel: `.fileImporter` did not open from the menu in this sheet (the Add
    /// button did nothing), and a panel also shows the folders of blocks in `~/Maps`. On iOS the system file picker is used.
    private func startImport(_ kind: ImportKind) {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = kind == .maps
        panel.allowedContentTypes = kind == .styles ? [.json] : [.folder, Self.storeType, .json]
        panel.message = kind == .styles ? "Choose style files (.json)" : "Choose a store file (.gmk) or a folder of blocks"
        panel.begin { response in
            guard response == .OK else { return }
            finishImport(panel.urls)
        }
        #else
        importing = kind
        #endif
    }

    /// Adds what was chosen: a map is opened, a style is applied to the map that is open.
    private func finishImport(_ urls: [URL]) {
        let added = library.add(urls)
        errors = added.errors
        if let id = added.maps.first {
            library.selectedMapID = id
        } else if let id = added.styles.first, let map = library.selectedMapID {
            library.setStyleChoice(.user(id), forMap: map)
        }
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
            #if os(iOS)
            if map.kind == .file {
                Button { send(map) } label: { Label("Send to the Watch", systemImage: "applewatch") }
            }
            #endif
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
            if let item {
                Button { edit(item) } label: { Label("Edit…", systemImage: "slider.horizontal.3") }
            } else {
                Button { copy(choice, named: name) } label: { Label("Edit a copy…", systemImage: "slider.horizontal.3") }
            }
            if item != nil {
                Button { copy(choice, named: name) } label: { Label("Make a copy", systemImage: "doc.on.doc") }
            }
            if let item {
                Button { begin(.style(item)) } label: { Label("Rename…", systemImage: "pencil") }
                ShareLink(item: library.url(of: item))
                Button(role: .destructive) { remove(item) } label: { Label("Remove", systemImage: "trash") }
            }
        }
        .swipeActions {
            if let item {
                Button(role: .destructive) { remove(item) } label: { Label("Remove", systemImage: "trash") }
                Button { edit(item) } label: { Label("Edit", systemImage: "slider.horizontal.3") }.tint(.indigo)
            }
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

    #if os(iOS)
    private func send(_ map: MapItem) {
        do {
            try watch.send(library.url(of: map), named: map.name)
        } catch {
            errors = [.failed(map.name, error.localizedDescription)]
        }
    }
    #endif

    /// Asks the map screen to open the style in the editor, and closes the library.
    private func edit(_ item: StyleItem) {
        library.styleToEdit = item.id
        dismiss()
    }

    /// A copy of a style (a built-in one to change, or one of the user's); a copy of a built-in style is opened in the editor.
    private func copy(_ choice: StyleChoice, named name: String) {
        do {
            let style = try library.style(for: choice)
            let item = try library.addStyle(style, named: "\(name) copy")
            if choice == .standard || choice == .watch { edit(item) }
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
