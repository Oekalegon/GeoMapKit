import AppKit
import SwiftUI

/// A small Mac app to try `MapView` on a feature store file: `swift run mapviewer [file.gmk]`.
///
/// It is a test tool, not a product: it shows the map with pan (drag) and zoom (pinch, or the buttons), lets you pick
/// the standard or Watch style or a JSON style file, and can shrink the view to a Watch screen size. Start it from
/// the `Tools` package; it has no bundle, so it activates itself.
/// The command line of the viewer: `[file.gmk] [--zoom Z] [--style standard|watch] [--watch-size] [--snapshot out.png]`.
///
/// `--snapshot` writes the window content to a PNG after the map has been drawn and quits, so the view can be
/// checked without a screen recording permission.
struct ViewerOptions {
    var path: String?
    var zoom: Double?
    var style: ViewerView.StyleChoice?
    var watchSize = false
    var snapshot: String?

    init(arguments: [String]) {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            func value() -> String? { index + 1 < arguments.count ? arguments[index + 1] : nil }
            switch argument {
            case "--zoom": zoom = value().flatMap(Double.init); index += 1
            case "--style": style = value().flatMap { $0 == "watch" ? .watch : .standard }; index += 1
            case "--snapshot": snapshot = value(); index += 1
            case "--watch-size": watchSize = true
            default: if path == nil, !argument.hasPrefix("--") { path = argument }
            }
            index += 1
        }
    }
}

/// Makes the executable a regular app with a window, since it has no bundle to say so.
final class ViewerAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct MapViewerApp: App {
    @NSApplicationDelegateAdaptor(ViewerAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("GeoMapKit Viewer") {
            ViewerView(options: ViewerOptions(arguments: Array(CommandLine.arguments.dropFirst())))
        }
    }
}
