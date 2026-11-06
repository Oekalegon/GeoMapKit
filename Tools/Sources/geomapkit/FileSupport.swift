import Foundation
import ToolSupport

func fileSize(_ url: URL) throws -> Int64 {
    guard FileManager.default.fileExists(atPath: url.path) else { throw ToolError("No such file: \(url.path)") }
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.size] as? NSNumber)?.int64Value ?? 0
}

/// File size divided by time, as megabytes per second.
func throughput(_ size: Int64, _ duration: Duration) -> String {
    let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    guard seconds > 0 else { return "-" }
    return String(format: "%.0f MB/s of file", Double(size) / 1e6 / seconds)
}
