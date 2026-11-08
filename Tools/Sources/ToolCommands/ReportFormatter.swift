import FeatureStore
import FeatureStoreBuilder
import GeoCore
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

    /// The text for a render.
    public static func text(for report: RenderReport) -> String {
        var lines = [
            "Render",
            "  image: \(report.outputName), \(report.pixelWidth) x \(report.pixelHeight) px, \(Formatting.bytes(Int64(report.pngBytes)))",
            "  scene: \(Formatting.seconds(report.sceneTime)), \(report.band) band, \(report.cellCount) cells, \(Formatting.count(report.featureCount)) features in \(report.stepCount) steps",
            "  draw:  \(Formatting.seconds(report.drawTime)) (draw and PNG encode)",
        ]
        if let built = report.outdatedRuleTable, let current = report.currentRuleTable {
            lines.append("")
            lines.append("note: the store was built with rule table \(built), this tool builds with \(current). Classes added since (for example the sea, sidewalks and road areas) are missing; rebuild the store to get them.")
        }
        return lines.joined(separator: "\n")
    }

    /// The text for an inspection.
    public static func text(for report: InspectReport) -> String {
        let total = report.objectsByClass.reduce(0) { $0 + $1.objects }
        var lines = ["Objects in \(report.fileName) by class (\(Formatting.count(total)) in all)"]
        for row in report.objectsByClass {
            lines.append("  \(pad(row.name, 14)) \(pad(Formatting.count(row.objects), 11, left: true))")
        }
        if let name = report.inspectedClass {
            lines.append("")
            lines.append("Most common tags in class \(name)")
            for row in report.topTags { lines.append("  \(pad(Formatting.count(row.objects), 9, left: true))  \(row.tag)") }
            lines.append("")
            lines.append("Most common keys in class \(name)")
            for row in report.topKeys { lines.append("  \(pad(Formatting.count(row.objects), 9, left: true))  \(row.tag)") }
        }
        return lines.joined(separator: "\n")
    }

    /// The text for a build: the cut, then the file and what went into it.
    public static func text(for report: BuildCommandReport) -> String {
        let statistics = report.statistics
        let counters = report.report
        var lines = [
            text(for: report.cut),
            "",
            "Build (\(report.profile == .full ? "full" : "watch") profile)",
            "  cut:   \(Formatting.seconds(report.cut.totalTime))",
            "  build: \(Formatting.seconds(report.buildTime))",
            "  file:  \(report.outputName), \(Formatting.bytes(Int64(statistics.fileBytes))), \(Formatting.count(statistics.cellCount)) cells written (verified)",
            "  extent: \(extentText(report.storedExtent))\(report.cut.area == report.requestedArea ? "" : " (the cut box was widened to whole cells)")",
            "  parts: cells \(Formatting.bytes(Int64(statistics.cellBytes))), strings \(Formatting.bytes(Int64(statistics.stringTableBytes))) (\(Formatting.count(statistics.stringCount)) strings), relations \(Formatting.bytes(Int64(statistics.relationTableBytes)))",
            "",
            "\(pad("Band", 8)) \(pad("bytes", 12, left: true)) \(pad("features", 10, left: true))",
        ]
        for band in ZoomBand.allCases {
            let bytes = statistics.bandBytes[band, default: 0]
            let features = statistics.featureCounts[band, default: 0]
            lines.append("\(pad(String(describing: band), 8)) \(pad(Formatting.bytes(Int64(bytes)), 12, left: true)) \(pad(Formatting.count(features), 10, left: true))")
        }
        lines += ["", "Features per class (detail band)"]
        let byClass = statistics.detailFeaturesByClass.sorted { $0.key < $1.key }
        for (rawValue, count) in byClass {
            let name = FeatureClass(rawValue: rawValue).map { String(describing: $0) } ?? "unknown(\(rawValue))"
            lines.append("  \(pad(name, 16)) \(pad(Formatting.count(count), 9, left: true))")
        }
        lines += [
            "",
            "Builder",
            "  nodes stored:     \(Formatting.count(counters.nodesStored))",
            "  ways:             \(Formatting.count(counters.waysStored)) stored, \(Formatting.count(counters.waysSuppressed)) suppressed (multipolygon members)",
            "  relations stored: \(Formatting.count(counters.relationsStored))",
            "  multipolygons:    \(Formatting.count(counters.multipolygonsAssembled)) assembled, \(Formatting.count(counters.multipolygonsIncomplete)) incomplete",
            "  footways beside roads: \(Formatting.count(counters.footwaysBesideRoads)) taken for sidewalks, \(Formatting.count(counters.footwaysInTown)) more in built-up areas",
            "  sea:              \(Formatting.count(counters.coastlineWays)) coastline ways, \(Formatting.count(counters.seaPolygons)) sea polygons, \(Formatting.count(counters.seaIslands)) islands",
            "  pieces outside the cells: \(Formatting.count(counters.piecesOutsideCells))",
            "  features skipped by the profile: \(Formatting.count(counters.featuresSkippedByProfile))",
        ]
        lines += extentWarning(for: report)
        if counters.seaOpenEnds > 0 {
            lines += [
                "",
                "warning: no sea was drawn. \(Formatting.count(counters.seaOpenEnds)) coastline end(s) lie inside the stored area, or a coastline way has a node missing, so the side the water is on cannot be followed to the edge of the area. This happens where the extract stops at a country border. Move the box edge out of the border area, or accept a map without the sea fill.",
            ]
        }
        return lines.joined(separator: "\n")
    }

    private static func extentText(_ box: BoundingBox) -> String {
        String(format: "south %.4f, west %.4f, north %.4f, east %.4f", box.south, box.west, box.north, box.east)
    }

    /// The warning lines for a file that does not cover the box it was asked for, or none.
    ///
    /// Only cells that lie completely inside the box are written, so a box edge that cuts through a cell drops the
    /// whole cell. The fix is a wider box.
    private static func extentWarning(for report: BuildCommandReport) -> [String] {
        let width = ExtentShortfall.oneCellInDegrees
        if report.statistics.cellCount == 0 {
            return ["", "warning: no cell lies completely inside the box, so nothing was stored. Use a box at least \(String(format: "%.3f", 2 * width)) degrees wide and high."]
        }
        let shortfall = report.shortfall
        guard !shortfall.isEmpty else { return [] }
        var sides: [String] = []
        for (name, degrees) in [("south", shortfall.south), ("west", shortfall.west), ("north", shortfall.north), ("east", shortfall.east)]
        where degrees > 0 {
            sides.append("\(name) by \(String(format: "%.3f", degrees))")
        }
        return [
            "",
            "warning: the file covers less than the box you asked for (\(sides.joined(separator: ", ")) degrees).",
            "         Only cells that lie completely inside the box are written, so a box edge that cuts a cell drops that cell.",
            String(format: "         Widen the box by about one cell (%.3f degrees) on those sides to cover it.", width),
        ]
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
