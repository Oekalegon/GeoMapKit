import Foundation
import OSMPBF
import ToolSupport

/// Turns reports into the text the tool prints.
public enum ReportFormatter {
    /// The text for a scan.
    public static func text(for report: ScanReport) -> String {
        var lines = [
            "File:      \(report.fileName), \(Formatting.bytes(report.fileSize))",
            "Header:    \(report.header.writingProgram ?? "unknown writer"), features \(report.header.requiredFeatures + report.header.optionalFeatures)",
        ]
        if let box = report.header.boundingBox {
            lines.append("Header box: south \(box.south), west \(box.west), north \(box.north), east \(box.east)")
        }
        lines.append("Objects:   \(Formatting.count(report.nodes)) nodes, \(Formatting.count(report.ways)) ways, \(Formatting.count(report.relations)) relations in \(Formatting.count(report.blocks)) blocks")
        lines.append("Decode:    \(Formatting.seconds(report.decodeTime)), \(rate(report.fileSize, report.decodeTime)) of file")
        lines.append(memoryLine(footprint: report.peakFootprint, resident: report.peakResident))
        return lines.joined(separator: "\n")
    }

    /// The text for a cut.
    public static func text(for report: CutReport) -> String {
        let area = report.area
        var lines = [
            "File: \(report.fileName), \(Formatting.bytes(report.fileSize))",
            "Area: south \(area.south), west \(area.west), north \(area.north), east \(area.east)",
            "",
            "\(pad("Pass", 24)) \(pad("time", 9, left: true)) \(pad("file rate", 11, left: true))   peak memory so far",
        ]
        for timing in report.passes {
            let isFilePass = timing.pass != .assembly
            let fileRate = isFilePass ? rate(report.fileSize, timing.duration) : "-"
            lines.append("\(pad(describe(timing.pass), 24)) \(pad(Formatting.seconds(timing.duration), 9, left: true)) \(pad(fileRate, 11, left: true))   \(Formatting.bytes(timing.peakMemoryAtStart))")
        }
        lines.append("Total: \(Formatting.seconds(report.totalTime))")
        lines.append(memoryLine(footprint: report.peakFootprint, resident: report.peakResident))
        let summary = report.summary
        lines += [
            "",
            "Extract",
            "  nodes:     \(Formatting.count(summary.nodes)) (\(Formatting.count(summary.taggedNodes)) tagged, \(Formatting.count(summary.nodesOutsideBox)) outside the box)",
            "  ways:      \(Formatting.count(summary.ways))",
            "  relations: \(Formatting.count(summary.relations)) (\(Formatting.count(summary.incompleteRelations)) incomplete)",
            "  nodes referenced but missing from the file: \(summary.missingNodes)",
            "  way vertices: \(Formatting.count(summary.wayVertices))",
            "  extract in memory: \(Formatting.bytes(Int64(summary.memoryBytes)))",
        ]
        return lines.joined(separator: "\n")
    }

    private static func rate(_ bytes: Int64, _ duration: Duration) -> String {
        Throughput.megabytesPerSecond(bytes: bytes, duration: duration).map { String(format: "%.0f MB/s", $0) } ?? "-"
    }

    private static func memoryLine(footprint: Int64?, resident: Int64) -> String {
        "Peak memory: footprint \(footprint.map(Formatting.bytes) ?? "n/a") (heap, what the cut needs); resident \(Formatting.bytes(resident)) (includes touched pages of the mapped file)"
    }

    private static func pad(_ text: String, _ width: Int, left: Bool = false) -> String {
        let padding = String(repeating: " ", count: max(0, width - text.count))
        return left ? padding + text : text + padding
    }

    private static func describe(_ pass: AreaCutter.Pass) -> String {
        switch pass {
        case .insideNodes: "1 nodes inside box"
        case .ways: "2 ways touching box"
        case .relations: "3 relations"
        case .memberWays: "4 relation member ways"
        case .outsideNodes: "5 nodes outside box"
        case .assembly: "assembly (in memory)"
        }
    }
}
