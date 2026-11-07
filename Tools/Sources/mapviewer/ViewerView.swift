import AppKit
import FeatureStore
import GeoCore
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

    @State private var store: FeatureStoreFile?
    @State private var storeName = ""
    @State private var center = Coordinate(latitude: 47.14, longitude: 9.52)
    @State private var zoom = 14.0
    @State private var choice = StyleChoice.standard
    @State private var customStyle: MapStyle?
    @State private var watchSize = false
    @State private var message: String?
    @State private var importing: Importing?

    private enum Importing: Identifiable {
        case store, style
        var id: Self { self }
    }

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
                    MapView(file: store, style: style, center: $center, zoom: $zoom)
                        .id(storeName)
                        .frame(width: watchSize ? 184 : nil, height: watchSize ? 224 : nil)
                        .border(watchSize ? Color.secondary : .clear)
                } else {
                    Text(message ?? "Open a .gmk feature store file").foregroundStyle(.secondary).padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.5, opacity: 0.1))
        }
        .frame(minWidth: 520, minHeight: 420)
        .fileImporter(
            isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }),
            allowedContentTypes: importing == .style ? [.json] : [UTType(filenameExtension: "gmk") ?? .data]
        ) { result in
            guard case .success(let url) = result else { return }
            if importing == .style { loadStyle(url.path) } else { loadStore(url.path) }
        }
        .task {
            if let path = options.path { loadStore(path) }
            if let zoom = options.zoom { self.zoom = zoom }
            if let style = options.style { choice = style }
            watchSize = options.watchSize
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
            .onChange(of: choice) { _, new in if new == .file && customStyle == nil { importing = .style } }
            if choice == .file { Button("Style file…") { importing = .style } }
            Toggle("Watch size", isOn: $watchSize)
            Spacer()
            Button("−") { zoom = max(zoom - 1, MapView.zoomRange.lowerBound) }
            Text(String(format: "z%.2f", zoom)).monospacedDigit()
            Button("+") { zoom = min(zoom + 1, MapView.zoomRange.upperBound) }
            Text(String(format: "%.5f, %.5f", center.latitude, center.longitude)).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(8)
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

    private func loadStore(_ path: String) {
        do {
            let file = try FeatureStoreFile(contentsOf: URL(fileURLWithPath: path))
            let box = file.boundingBox
            center = Coordinate(latitude: (box.south + box.north) / 2, longitude: (box.west + box.east) / 2)
            zoom = 14
            storeName = path
            store = file
            message = nil
        } catch {
            store = nil
            message = "Cannot open \(path): \(error)"
        }
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
