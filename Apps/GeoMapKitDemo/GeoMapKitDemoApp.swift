import SwiftUI

/// The test app of GeoMapKit: a map of the stores in the library, with their styles.
@main
struct GeoMapKitDemoApp: App {
    @State private var library = MapLibrary()
    @State private var watch = WatchLink()

    var body: some Scene {
        WindowGroup {
            MapScreen()
                .environment(library)
                .environment(watch)
                // A store or a style that was opened with this app from the Files app, AirDrop or Finder.
                .onOpenURL { url in
                    // The map that was just added is the one to look at.
                    if let id = library.add([url]).maps.first { library.selectedMapID = id }
                }
        }
    }
}
