import Foundation
import GeoCore
import OSMPBF
import ToolSupport

/// Runs the tool commands and returns reports; printing is left to the caller.
public enum ToolRunner {
    /// Decodes a whole file once.
    ///
    /// - Parameter url: The PBF file.
    /// - Returns: Counts, time and memory.
    /// - Throws: ``ToolError`` if the file is missing, or a `PBFError` if it is malformed.
    public static func scan(url: URL) throws -> ScanReport {
        let size = try fileSize(url)
        let reader = try PBFReader(url: url)
        let header = try reader.header()
        var blocks = 0, nodes = 0, ways = 0, relations = 0
        let elapsed = try ContinuousClock().measure {
            try reader.forEachBlock { block in
                blocks += 1
                nodes += block.nodes.count
                ways += block.ways.count
                relations += block.relations.count
            }
        }
        return ScanReport(
            fileName: url.lastPathComponent, fileSize: size, header: header, blocks: blocks,
            nodes: nodes, ways: ways, relations: relations, decodeTime: elapsed,
            peakFootprint: ProcessMemory.peakFootprintBytes(), peakResident: ProcessMemory.peakResidentBytes()
        )
    }

    /// Cuts an area out of a file and times each pass.
    ///
    /// - Parameters:
    ///   - url: The PBF file.
    ///   - area: The area to cut.
    ///   - options: The cutter settings.
    /// - Returns: Timings, memory and what the extract contains.
    /// - Throws: ``ToolError`` if the file is missing, or whatever the cutter throws.
    public static func cut(url: URL, area: BoundingBox, options: AreaCutter.Options = .init()) throws -> CutReport {
        let size = try fileSize(url)
        let reader = try PBFReader(url: url)

        // Each stage lasts from its start to the start of the next stage (or the end).
        let clock = ContinuousClock()
        var starts: [(pass: AreaCutter.Pass, instant: ContinuousClock.Instant, memory: Int64)] = []
        let begin = clock.now
        let extract = try AreaCutter(options: options).cut(reader, to: area) { pass in
            starts.append((pass, clock.now, ProcessMemory.peakFootprintBytes() ?? ProcessMemory.peakResidentBytes()))
        }
        let end = clock.now

        let passes = starts.enumerated().map { index, start in
            let finish = index + 1 < starts.count ? starts[index + 1].instant : end
            return PassTiming(pass: start.pass, duration: finish - start.instant, peakMemoryAtStart: start.memory)
        }
        return CutReport(
            fileName: url.lastPathComponent, fileSize: size, area: area, passes: passes, totalTime: end - begin,
            summary: ExtractSummary(extract),
            peakFootprint: ProcessMemory.peakFootprintBytes(), peakResident: ProcessMemory.peakResidentBytes()
        )
    }

    private static func fileSize(_ url: URL) throws -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { throw ToolError("No such file: \(url.path)") }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
}
