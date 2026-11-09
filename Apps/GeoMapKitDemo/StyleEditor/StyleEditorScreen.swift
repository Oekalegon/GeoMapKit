import FeatureStore
import GeoCore
import MapStyle
import MapUI
import SwiftUI

/// What the preview of the editor shows: the map that is open, where the map is.
struct PreviewMap {
    let opened: OpenedMap
    let center: Coordinate
    let zoom: Double
}

/// A style being edited, for `sheet(item:)`.
struct EditorSession: Identifiable {
    let model: StyleEditorModel
    let preview: PreviewMap?
    var id: String { model.item.id }
}

/// The style editor: the map on top with the style as it is now, and below it the general settings, the classes (a form for each) and the
/// JSON of the style. The preview stays when a class is opened.
struct StyleEditorScreen: View {
    @Environment(MapLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    let session: EditorSession

    private enum Tab: Hashable { case general, classes, json }

    @State private var tab = Tab.classes
    @State private var center = Coordinate(latitude: 0, longitude: 0)
    @State private var zoom = 10.0
    @State private var bearing = 0.0
    @State private var error: String?
    @State private var confirmingClose = false

    private var model: StyleEditorModel { session.model }

    var body: some View {
        VStack(spacing: 0) {
            preview
                #if os(macOS)
                .frame(height: 340)
                #else
                .frame(height: 260)
                #endif
            Divider()
            NavigationStack {
                VStack(spacing: 0) {
                    Picker("Part", selection: $tab) {
                        Text("General").tag(Tab.general)
                        Text("Classes").tag(Tab.classes)
                        Text("JSON").tag(Tab.json)
                    }
                    .pickerStyle(.segmented).padding(8)
                    switch tab {
                    case .general: GeneralEditorView(model: model)
                    case .classes: ClassListView(model: model)
                    case .json: JSONEditorView(model: model)
                    }
                }
                .navigationTitle(model.item.name)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbar }
            }
        }
        .onAppear {
            if let preview = session.preview {
                center = preview.center
                zoom = preview.zoom
            }
        }
        .confirmationDialog("Save the changes to \(model.item.name)?", isPresented: $confirmingClose, titleVisibility: .visible) {
            Button("Save") { if save() { dismiss() } }
            Button("Don't save", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .alert("Could not save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 720)
        #endif
    }

    @ViewBuilder private var preview: some View {
        if let preview = session.preview {
            MapView(source: preview.opened.source, style: model.style, center: $center, zoom: $zoom, bearing: $bearing)
                .id(preview.opened.id)
        } else {
            ContentUnavailableView("No map open", systemImage: "map", description: Text("Open a map to see the style on it."))
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") { if model.isDirty { confirmingClose = true } else { dismiss() } }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }.disabled(!model.canUndo)
            Button { model.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }.disabled(!model.canRedo)
            Button("Save") { _ = save() }.disabled(!model.isDirty)
        }
    }

    private func save() -> Bool {
        do {
            try model.save(into: library)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
