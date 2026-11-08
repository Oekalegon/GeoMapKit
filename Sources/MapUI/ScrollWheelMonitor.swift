#if os(macOS)
import AppKit
import MapRender
import SwiftUI

/// Reports scroll events over its own area to a handler, without taking mouse clicks or drags from the views around it.
///
/// A mouse wheel has no gesture in SwiftUI, so the view listens to the scroll events of its window and passes on those that
/// lie inside its frame. Events for another window (a sheet or a popover over the map) are ignored. The events are not consumed,
/// so a scroll view around the map would still see them.
struct ScrollWheelMonitor: NSViewRepresentable {
    /// What a scroll event carries: where the pointer was, the deltas, and whether they come from a trackpad (precise, in points)
    /// or from a wheel (in lines).
    struct Scroll {
        var pointer: ScreenPoint
        var dx: Double
        var dy: Double
        var precise: Bool
    }

    var handler: (Scroll) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.handler = handler
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) { view.handler = handler }

    final class MonitorView: NSView {
        var handler: (Scroll) -> Void = { _ in }
        private var monitor: Any?

        override var isFlipped: Bool { true }
        /// Never the target of a click: the gestures of the map see them.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        /// Removes the monitor as soon as the view is taken out of its window, or the window closes.
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.receive(event)
                return event
            }
        }

        private func receive(_ event: NSEvent) {
            guard event.window === window else { return }
            let point = convert(event.locationInWindow, from: nil)
            guard bounds.contains(point) else { return }
            handler(
                Scroll(
                    pointer: ScreenPoint(x: point.x, y: point.y), dx: event.scrollingDeltaX, dy: event.scrollingDeltaY,
                    precise: event.hasPreciseScrollingDeltas))
        }
    }
}
#endif
