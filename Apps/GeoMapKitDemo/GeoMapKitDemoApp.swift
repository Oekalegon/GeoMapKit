import SwiftUI

/// The test app of GeoMapKit: a map of the stores in the library, with their styles.
@main
struct GeoMapKitDemoApp: App {
    @State private var library: MapLibrary
    @State private var sync: StyleSync
    @State private var watch = WatchLink()

    init() {
        let library = MapLibrary()
        _library = State(initialValue: library)
        _sync = State(initialValue: StyleSync(library: library))
    }

    var body: some Scene {
        WindowGroup {
            MapScreen()
                .environment(library)
                .environment(watch)
                .environment(sync)
                // The styles go to iCloud when it is there: a build without the iCloud entitlement finds no container and keeps them here.
                .task { if sync.isEnabled { sync.start() } }
                // A store or a style that was opened with this app from the Files app, AirDrop or Finder.
                .onOpenURL { url in
                    // The map that was just added is the one to look at.
                    if let id = library.add([url]).maps.first { library.selectedMapID = id }
                }
        }
    }
}
