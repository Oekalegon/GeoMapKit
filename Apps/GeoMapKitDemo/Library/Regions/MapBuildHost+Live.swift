#if os(macOS)
import AppKit
import Regions

extension MapBuildHost {
    /// The host of the app: the Geofabrik list and the source files go to the cache folder of the app, and the maps are built in `Maps`
    /// next to it and added to the library. A finished map is not opened by itself: the user is looking at another map, and the status
    /// bar offers to show it.
    static func live(library: MapLibrary) -> MapBuildHost {
        MapBuildHost {
            let directory = try SourceCache.defaultDirectory()
            let downloader = URLSessionDownloader(userAgent: MapBuildTools.userAgent)
            let catalog = GeofabrikCatalog(directory: directory, downloader: downloader)
            let picker = RegionPickerModel(catalog: catalog, downloader: downloader, cache: SourceCache(directory: directory))
            return MapBuildModel(
                picker: picker, catalog: catalog, mapsRoot: directory.deletingLastPathComponent().appendingPathComponent("Maps", isDirectory: true)
            ) { folder, name in try library.addBuilt(folder: folder, name: name) }
        }
    }
}

/// Asks before the app quits while a map is built: the build stops, and what is downloaded and built is kept for the next start.
final class QuitGuard: NSObject, NSApplicationDelegate {
    /// The host whose run is asked about; set when the app starts.
    @MainActor static weak var host: MapBuildHost?

    @MainActor func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard Self.host?.isRunning == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "A map is being built"
        alert.informativeText = "If you quit, the build stops. What was downloaded and built is kept, and you can continue it later."
        alert.addButton(withTitle: "Keep building")
        alert.addButton(withTitle: "Quit")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
#endif
