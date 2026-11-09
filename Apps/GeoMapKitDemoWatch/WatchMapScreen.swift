import FeatureStore
import GeoCore
import MapStyle
import MapUI
import SwiftUI

/// One map on the Watch: the Watch style, the Digital Crown zooms and a drag pans. It is drawn when something changes and not otherwise.
struct WatchMapScreen: View {
    let map: WatchMapEntry

    @State private var file: FeatureStoreFile?
    @State private var center = Coordinate(latitude: 0, longitude: 0)
    @State private var zoom = 13.0
    @State private var bearing = 0.0
    @State private var error: String?

    var body: some View {
        Group {
            if let file {
                MapView(source: file, style: .watch, center: $center, zoom: $zoom, bearing: $bearing)
            } else if let error {
                Text(error).font(.footnote).padding()
            } else {
                ProgressView()
            }
        }
        .navigationTitle(map.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(map.id) \(map.date.timeIntervalSince1970)") { open() }
    }

    private func open() {
        do {
            let opened = try FeatureStoreFile(contentsOf: map.url)
            let start = WatchMapStore.start(of: opened)
            center = start.center
            zoom = start.zoom
            file = opened
        } catch {
            self.error = "This map cannot be read: \(error)"
        }
    }
}
