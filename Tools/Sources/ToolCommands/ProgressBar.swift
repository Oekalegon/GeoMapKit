import Foundation
import ToolSupport

/// Draws a ``BlockProgress`` as one line of text, for the terminal.
public enum ProgressBar {
    /// The line: `[ 57/163] ███████░░░░░░░░░░░░░  35 %  4 running  1:12:30 left`.
    ///
    /// - Parameters:
    ///   - progress: The progress.
    ///   - barWidth: The number of characters of the bar itself, at least 1.
    public static func line(for progress: BlockProgress, barWidth: Int = 20) -> String {
        let width = max(barWidth, 1)
        let filled = min(max(Int((progress.fraction * Double(width)).rounded(.down)), 0), width)
        let digits = String(progress.total).count
        let count = "\(pad(progress.finished, digits))/\(progress.total)"
        let percent = pad(Int((progress.fraction * 100).rounded(.down)), 3)
        var text = "[\(count)] " + String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled) + " \(percent) %"
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
    ///   - barWidth: The number of characters of the bar itself, at least 1.
    public static func downloadLine(id: String, bytes: Int64, total: Int64, barWidth: Int = 20) -> String {
        let width = max(barWidth, 1)
        let fraction = total > 0 ? min(max(Double(bytes) / Double(total), 0), 1) : 0
        let filled = min(Int(fraction * Double(width)), width)
        return "\(id)  " + String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
            + " \(pad(Int(fraction * 100), 3)) %  \(Formatting.bytes(bytes)) of \(Formatting.bytes(total))"
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
