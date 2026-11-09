import SwiftUI

/// The test app of GeoMapKit: a map of the stores in the library, with their styles.
@main
struct GeoMapKitDemoApp: App {
    @State private var library = MapLibrary()

    var body: some Scene {
        WindowGroup {
            MapScreen()
                .environment(library)
                // A store or a style that was opened with this app from the Files app, AirDrop or Finder.
                .onOpenURL { url in
                    let errors = library.add([url])
                    if errors.isEmpty, let map = library.maps.first(where: { $0.id.hasPrefix(url.deletingPathExtension().lastPathComponent) }) {
                        library.selectedMapID = map.id
                    }
                }
        }
    }
}
