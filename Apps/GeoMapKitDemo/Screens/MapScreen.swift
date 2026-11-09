import GeoCore
import MapRender
import MapStyle
import MapUI
import SwiftUI

/// The map of the selected store, with the library, the style and the position of the user.
struct MapScreen: View {
    @Environment(MapLibrary.self) private var library
    @State private var opened: OpenedMap?
    @State private var center = Coordinate(latitude: 59.9, longitude: 10.7)
    @State private var zoom = 3.0
    @State private var bearing = 0.0
    @State private var style: MapStyle = .standard
    @State private var message: String?
    @State private var showLibrary = false
    @State private var location = LocationModel()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                if let opened {
                    GeometryReader { proxy in
                        ZStack {
                            MapView(source: opened.source, style: style, center: $center, zoom: $zoom, bearing: $bearing)
                                .id(opened.id)
                            locationDot(in: proxy.size)
                        }
                    }
                    // The map runs under the home indicator; the title bar stays.
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView {
                        Label("No map yet", systemImage: "map")
                    } description: {
                        Text("Add a feature store (.gmk) or a folder of blocks in the library.")
                    } actions: {
                        Button("Open the library") { showLibrary = true }.buttonStyle(.borderedProminent)
                    }
                }
                if opened != nil, library.styleChoice(forMap: library.selectedMapID) == .watch, zoom < 12 {
                    // The Watch style draws nothing below zoom 12 (the Watch holds the mid and detail bands only).
                    Text("The Watch style shows the map from zoom 12.")
                        .font(.footnote).padding(8).background(.regularMaterial, in: Capsule()).padding(8)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                if let message {
                    Text(message)
                        .font(.footnote).multilineTextAlignment(.center)
                        .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(8)
                        .onTapGesture { self.message = nil }
                }
            }
            .navigationTitle(library.maps.first { $0.id == library.selectedMapID }?.name ?? "GeoMapKit")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
        }
        .sheet(isPresented: $showLibrary) { LibraryScreen().environment(library) }
        .task(id: library.selectedMapID) { loadMap() }
        .onChange(of: library.revision) { _, _ in loadStyle() }
        .onDisappear { location.stop() }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showLibrary = true } label: { Label("Library", systemImage: "books.vertical") }
        }
        ToolbarItem(placement: .primaryAction) { styleMenu }
        ToolbarItem(placement: .primaryAction) {
            Button(action: centreOnMe) { Label("Centre on me", systemImage: location.denied ? "location.slash" : "location") }
                .help(location.denied ? "Location is off for this app: turn it on in the settings." : "Centre the map on your position")
        }
        #if os(macOS)
        ToolbarItemGroup(placement: .automatic) {
            Button { zoom = max(zoom - 1, MapView.zoomRange.lowerBound) } label: { Label("Zoom out", systemImage: "minus") }
            Button { zoom = min(zoom + 1, MapView.zoomRange.upperBound) } label: { Label("Zoom in", systemImage: "plus") }
        }
        #endif
    }

    private var styleMenu: some View {
        Menu {
            let selected = library.selectedMapID
            let current = library.styleChoice(forMap: selected)
            Picker("Style", selection: Binding(
                get: { current },
                set: { choice in if let selected { library.setStyleChoice(choice, forMap: selected) } })
            ) {
                Text("Standard").tag(StyleChoice.standard)
                Text("Watch").tag(StyleChoice.watch)
                ForEach(library.styles) { Text($0.name).tag(StyleChoice.user($0.id)) }
            }
        } label: {
            Label("Style", systemImage: "paintpalette")
        }
        .disabled(library.selectedMapID == nil)
    }

    // MARK: Position

    @ViewBuilder private func locationDot(in size: CGSize) -> some View {
        if let coordinate = location.coordinate {
            let point = MapViewport(center: center, zoom: zoom, width: size.width, height: size.height, bearing: bearing).screenPoint(for: coordinate)
            Circle().fill(.blue).frame(width: 14, height: 14)
                .overlay(Circle().stroke(.white, lineWidth: 2.5))
                .shadow(radius: 2)
                .position(x: point.x, y: point.y)
                .allowsHitTesting(false)
        }
    }

    private func centreOnMe() {
        location.start()
        if let coordinate = location.coordinate {
            center = coordinate
            zoom = max(zoom, 13)
        } else if !location.denied {
            message = "Waiting for your position…"
        } else {
            message = "Location is off for this app: turn it on in the settings."
        }
    }

    // MARK: Loading

    private func loadMap() {
        message = nil
        guard let id = library.selectedMapID, let item = library.maps.first(where: { $0.id == id }) else {
            opened = nil
            return
        }
        do {
            let map = try library.open(item)
            center = map.center
            zoom = map.zoom
            bearing = 0
            opened = map
            loadStyle()
        } catch {
            opened = nil
            message = "Cannot open \(item.name): \(error.localizedDescription)"
        }
    }

    private func loadStyle() {
        do {
            style = try library.style(for: library.styleChoice(forMap: library.selectedMapID))
        } catch {
            style = .standard
            message = error.localizedDescription
        }
    }
}
