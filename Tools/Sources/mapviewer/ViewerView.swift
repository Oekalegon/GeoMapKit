import AppKit
import FeatureStore
import FeatureStoreBuilder
import GeoCore
import MapRender
import MapStyle
import MapUI
import SwiftUI
import UniformTypeIdentifiers

/// The window content of the viewer: a toolbar and a `MapView`.
struct ViewerView: View {
    /// The built-in styles and a style loaded from a file.
    enum StyleChoice: String, CaseIterable, Identifiable {
        case standard = "Standard"
        case watch = "Watch"
        case file = "File"
        var id: String { rawValue }
    }

    let options: ViewerOptions

    @State private var store: (any CellSource)?
    @State private var storeName = ""
    @State private var center = Coordinate(latitude: 47.14, longitude: 9.52)
    @State private var zoom = 14.0
    @State private var bearing = 0.0
    @State private var choice = StyleChoice.standard
    @State private var customStyle: MapStyle?
    @State private var watchSize = false
    @State private var message: String?
    @State private var outdatedNote: String?
    @State private var importing: Importing?

    private enum Importing: Identifiable {
        case store, style
        var id: Self { self }
    }

    /// The Watch style draws nothing below this zoom (the Watch holds the mid and detail bands only).
    private static let watchMinimumZoom = 12.0

    /// What serves the view at this zoom, for a set of blocks that has levels: `level 6` or `blocks`.
    private var servedBy: String? { (store as? StoreSet).map { $0.levelName(forZoom: zoom) } }

    private var style: MapStyle {
        switch choice {
        case .standard: return .standard
        case .watch: return .watch
        case .file: return customStyle ?? .standard
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ZStack {
                if let store {
                    MapView(source: store, style: style, center: $center, zoom: $zoom, bearing: $bearing)
                        .id(storeName)
                        .frame(width: watchSize ? 184 : nil, height: watchSize ? 224 : nil)
                        .border(watchSize ? Color.secondary : .clear)
                        .overlay(alignment: .top) {
                            if let outdatedNote {
                                Text(outdatedNote)
                                    .font(.footnote).padding(6).background(.regularMaterial, in: Capsule()).padding(8)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if choice == .watch && zoom < Self.watchMinimumZoom {
                                Text("The Watch style shows the map from zoom 12.")
                                    .font(.footnote).padding(6).background(.regularMaterial, in: Capsule()).padding(8)
                            }
                        }
                } else {
                    Text(message ?? "Open a .gmk feature store file, or the manifest.json of a set of blocks").foregroundStyle(.secondary).padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.5, opacity: 0.1))
        }
        .frame(minWidth: 520, minHeight: 420)
        .fileImporter(
            isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }),
            allowedContentTypes: importing == .style ? [.json] : [UTType(filenameExtension: "gmk") ?? .data, .json, .folder]
        ) { result in
            guard case .success(let url) = result else { return }
            if importing == .style { loadStyle(url.path) } else { loadStore(url.path) }
        }
        .task {
            if let path = options.path { loadStore(path) }
            if let zoom = options.zoom { self.zoom = zoom }
            if let style = options.style { choice = style }
            watchSize = options.watchSize
            if let pan = options.pan { await scriptedPan(pan) }
            if let snapshot = options.snapshot { await takeSnapshot(to: snapshot) }
        }
    }

    private var toolbar: some View {
        HStack {
            Button("Open…") { importing = .store }
            Picker("Style", selection: $choice) {
                ForEach(StyleChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).frame(width: 220)
            .onChange(of: choice) { _, new in
                if new == .file && customStyle == nil { importing = .style }
                if new == .watch { zoom = max(zoom, Self.watchMinimumZoom) }
            }
            if choice == .file { Button("Style file…") { importing = .style } }
            Toggle("Watch size", isOn: $watchSize)
            Spacer()
            Button("−") {
                zoom = max(zoom - 1, choice == .watch ? Self.watchMinimumZoom : MapView.zoomRange.lowerBound)
            }
            Text(String(format: "z%.2f", zoom)).monospacedDigit()
            if let servedBy { Text(servedBy).foregroundStyle(.secondary) }
            Button("+") { zoom = min(zoom + 1, MapView.zoomRange.upperBound) }
            Text(String(format: "%.5f, %.5f", center.latitude, center.longitude)).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(8)
    }

    /// Moves the centre in 30 small steps, like a drag would, so panning can be checked without a mouse.
    @MainActor
    private func scriptedPan(_ pan: (x: Double, y: Double)) async {
        try? await Task.sleep(for: .seconds(1.5))
        for _ in 0..<30 {
            let view = MapViewport(center: center, zoom: zoom, width: 900, height: 700, bearing: bearing)
            center = view.coordinate(at: ScreenPoint(x: 450 + pan.x / 30, y: 350 + pan.y / 30))
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    /// Waits for the first frame, writes the window content to a PNG and quits.
    @MainActor
    private func takeSnapshot(to path: String) async {
        try? await Task.sleep(for: .seconds(3))
        FileHandle.standardError.write(Data("snapshot: \(NSApp.windows.count) windows\n".utf8))
        guard let view = NSApp.windows.first(where: { $0.contentView != nil })?.contentView,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else {
            FileHandle.standardError.write(Data("snapshot: no window content\n".utf8))
            NSApp.terminate(nil)
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        do {
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            FileHandle.standardError.write(Data("snapshot: wrote \(path)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("snapshot: \(error)\n".utf8))
        }
        NSApp.terminate(nil)
    }

    /// Opens a store: a `.gmk` file, a `manifest.json` of blocks, or a folder that holds a `manifest.json`.
    private func loadStore(_ path: String) {
        do {
            var url = URL(fileURLWithPath: path)
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                url = url.appendingPathComponent("manifest.json")
            }
            let source: any CellSource
            let box: BoundingBox
            let built: Int
            if url.pathExtension.lowercased() == "json" {
                let set = try StoreSet(manifestURL: url)
                guard let area = set.boundingBox else { throw StoreSetError.invalidManifest("the manifest lists no blocks") }
                source = set
                box = area
                built = set.manifest.classifierVersion
                zoom = 11
            } else {
                let file = try FeatureStoreFile(contentsOf: url)
                source = file
                box = file.boundingBox
                built = file.classifierVersion
                zoom = 14
            }
            center = Coordinate(latitude: (box.south + box.north) / 2, longitude: (box.west + box.east) / 2)
            if let set = source as? StoreSet, let start = Self.startCoordinate(in: set, near: center) { center = start }
            storeName = path
            store = source
            message = nil
            let current = Int(FeatureClassifier.version)
            outdatedNote = built < current
                ? "Built with rule table \(built), current is \(current): rebuild to get the newest map classes and bands."
                : nil
        } catch {
            store = nil
            message = "Cannot open \(path): \(error)"
        }
    }

    /// The middle of the block nearest to `point`: the middle of a large set may lie in the sea or in a tile with no block.
    private static func startCoordinate(in set: StoreSet, near point: Coordinate) -> Coordinate? {
        var best: (distance: Double, coordinate: Coordinate)?
        for block in set.manifest.blocks {
            guard let tile = TileID(zoom: set.manifest.blockZoom, x: block.x, y: block.y) else { continue }
            let middle = Coordinate(
                latitude: (tile.northWest.latitude + tile.southEast.latitude) / 2,
                longitude: (tile.northWest.longitude + tile.southEast.longitude) / 2)
            let d = pow(middle.latitude - point.latitude, 2) + pow((middle.longitude - point.longitude) * cos(point.latitude * .pi / 180), 2)
            if best == nil || d < best!.distance { best = (d, middle) }
        }
        return best?.coordinate
    }

    private func loadStyle(_ path: String) {
        do {
            customStyle = try MapStyle(json: Data(contentsOf: URL(fileURLWithPath: path)))
            choice = .file
        } catch {
            message = "\(path): \(error)"
        }
    }
}
