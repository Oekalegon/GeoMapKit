import SwiftUI

/// The Watch app: the maps the iPhone sent, and a map of each with the Watch style.
@main
struct GeoMapKitDemoWatchApp: App {
    @State private var link = WatchLink()

    var body: some Scene {
        WindowGroup {
            WatchMapList()
                .environment(link)
        }
    }
}
