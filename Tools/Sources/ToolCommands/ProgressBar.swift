import Foundation
import MapBuilder
import ToolSupport
#if canImport(Darwin)
import Darwin
#endif

/// Draws a ``BlockProgress`` as one line of text, for the terminal.
public enum ProgressBar {
    /// Whether standard error is a terminal that can redraw a line (not a pipe, a file or `TERM=dumb`).
    public static var isUsableTerminal: Bool {
        isatty(STDERR_FILENO) != 0 && ProcessInfo.processInfo.environment["TERM"] != "dumb"
    }

    /// The width of the terminal in characters, or 80 when it is not known.
    public static func terminalWidth() -> Int {
        var size = winsize()
        return ioctl(STDERR_FILENO, TIOCGWINSZ, &size) == 0 && size.ws_col > 0 ? Int(size.ws_col) : 80
    }

    /// The width for the bar so that a line of `fixed` other characters stays one column short of `terminal` (at most 20, at least 0).
    public static func barWidth(terminal: Int, fixed: Int) -> Int { min(max(terminal - fixed - 2, 0), 20) }

    /// The line: `[ 57/163] ███████░░░░░░░░░░░░░  35 %  4 running  1:12:30 left`.
    ///
    /// - Parameters:
    ///   - progress: The progress.
    ///   - barWidth: The number of characters of the bar itself; 0 leaves the bar out.
    ///   - terminalWidth: When given, the bar is made narrower so that the line fits (and is left out if it cannot).
    public static func line(for progress: BlockProgress, barWidth: Int = 20, terminalWidth: Int? = nil) -> String {
        var width = max(barWidth, 0)
        if let terminalWidth {
            width = min(width, self.barWidth(terminal: terminalWidth, fixed: line(for: progress, barWidth: 0).count))
        }
        let filled = min(max(Int((progress.fraction * Double(width)).rounded(.down)), 0), width)
        let digits = String(progress.total).count
        let count = "\(pad(progress.finished, digits))/\(progress.total)"
        let percent = pad(Int((progress.fraction * 100).rounded(.down)), 3)
        let bar = width > 0 ? String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled) + " " : ""
        var text = "[\(count)] " + bar + "\(percent) %"
        if progress.running > 0 { text += "  \(progress.running) running" }
        if let remaining = progress.remaining { text += "  \(clock(remaining)) left" }
        return text
    }

    /// The line of a download: `finland  ██████░░░░░░░░░░░░░░  30 %  232.7 MB of 775.5 MB`.
    ///
    /// - Parameters:
    ///   - id: The region id.
    ///   - bytes: The bytes received.
    ///   - total: The size of the file.
    ///   - barWidth: The number of characters of the bar itself; 0 leaves the bar out.
    ///   - terminalWidth: When given, the bar is made narrower so that the line fits (and is left out if it cannot).
    public static func downloadLine(id: String, bytes: Int64, total: Int64, barWidth: Int = 20, terminalWidth: Int? = nil) -> String {
        var width = max(barWidth, 0)
        if let terminalWidth {
            width = min(width, self.barWidth(terminal: terminalWidth, fixed: downloadLine(id: id, bytes: bytes, total: total, barWidth: 0).count))
        }
        let fraction = total > 0 ? min(max(Double(bytes) / Double(total), 0), 1) : 0
        let filled = min(Int(fraction * Double(width)), width)
        let bar = width > 0 ? String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled) + " " : ""
        return "\(id)  " + bar + "\(pad(Int(fraction * 100), 3)) %  \(Formatting.bytes(bytes)) of \(Formatting.bytes(total))"
    }

    /// A duration as `h:mm:ss`, or `m:ss` under an hour.
    public static func clock(_ duration: Duration) -> String {
        let seconds = max(Int(duration.components.seconds), 0)
        let h = seconds / 3600, m = seconds % 3600 / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: " ", count: max(width - text.count, 0)) + text
    }
}
