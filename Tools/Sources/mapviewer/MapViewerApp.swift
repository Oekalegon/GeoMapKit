import AppKit
import SwiftUI

/// The command line of the viewer: `[file.gmk] [--zoom Z] [--style standard|watch] [--watch-size] [--pan EAST,SOUTH] [--snapshot out.png]`.
///
/// `--snapshot` writes the window content to a PNG after the map has been drawn and quits, so the view can be
/// checked without a screen recording permission.
struct ViewerOptions {
    var path: String?
    var zoom: Double?
    var style: ViewerView.StyleChoice?
    var watchSize = false
    var snapshot: String?
    /// Moves the view by this many points (east, south) in small steps before the snapshot, to test panning.
    var pan: (x: Double, y: Double)?

    init(arguments: [String]) {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            func value() -> String? { index + 1 < arguments.count ? arguments[index + 1] : nil }
            switch argument {
            case "--zoom": zoom = value().flatMap(Double.init); index += 1
            case "--style": style = value().flatMap { $0 == "watch" ? .watch : .standard }; index += 1
            case "--snapshot": snapshot = value(); index += 1
            case "--pan":
                let parts = value()?.split(separator: ",").compactMap { Double($0) } ?? []
                if parts.count == 2 { pan = (parts[0], parts[1]) }
                index += 1
            case "--watch-size": watchSize = true
            default: if path == nil, !argument.hasPrefix("--") { path = argument }
            }
            index += 1
        }
    }
}

/// Makes the executable a regular app with a window, since it has no bundle to say so.
///
/// The window is made by hand (an `NSWindow` hosting the SwiftUI view) rather than with a SwiftUI `App`: a SwiftUI
/// scene is created before the activation policy of an unbundled executable can be set, and then no window appears.
@MainActor
final class ViewerAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let options = ViewerOptions(arguments: Array(CommandLine.arguments.dropFirst()))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "GeoMapKit Viewer"
        window.contentViewController = NSHostingController(rootView: ViewerView(options: options))
        window.setContentSize(NSSize(width: 900, height: 700))
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// A small Mac app to try `MapView` on a feature store file: `swift run mapviewer [file.gmk]`.
///
/// It is a test tool, not a product: it shows the map with pan (drag) and zoom (pinch, or the buttons), lets you pick
/// the standard or Watch style or a JSON style file, and can shrink the view to a Watch screen size. Start it from
/// the `Tools` package; it has no bundle, so it activates itself.
@main
enum MapViewerMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let delegate = ViewerAppDelegate()
        application.delegate = delegate
        application.run()
    }
}
