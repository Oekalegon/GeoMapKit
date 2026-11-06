import Foundation
import OSMPBF
import ToolSupport

/// `geomapkit cut`: cuts an area and reports where the time and memory go.
enum CutCommand {
    static func run(_ arguments: CommandLineArguments) throws {
        guard let path = arguments.positional.first else { throw ToolError("cut needs a file") }
        let box = try AreaArgument.parse(
            bbox: arguments.value(for: "bbox"), center: arguments.value(for: "center"),
            radiusKilometres: arguments.value(for: "radius-km")
        )
        var options = AreaCutter.Options()
        if let limit = arguments.value(for: "limit") {
            guard let value = Int(limit) else { throw ToolError("--limit expects a whole number") }
            options.relationMemberLimit = value
        }

        let url = URL(fileURLWithPath: path)
        let size = try fileSize(url)
        let reader = try PBFReader(url: url)
        print("File: \(url.lastPathComponent), \(Formatting.bytes(size))")
        print("Area: south \(box.south), west \(box.west), north \(box.north), east \(box.east)")

        // Time each pass from the moment it starts to the moment the next one starts.
        let clock = ContinuousClock()
        var passes: [(pass: AreaCutter.Pass, start: ContinuousClock.Instant, memory: Int64)] = []
        let begin = clock.now
        let extract = try AreaCutter(options: options).cut(reader, to: box) { pass in
            passes.append((pass, clock.now, ProcessMemory.peakResidentBytes()))
        }
        let end = clock.now

        print("\n\(pad("Pass", 24)) \(pad("time", 9, left: true)) \(pad("file rate", 11, left: true))   peak memory at start")
        for (index, entry) in passes.enumerated() {
            let finish = index + 1 < passes.count ? passes[index + 1].start : end
            let duration = finish - entry.start
            let isFilePass = entry.pass != .assembly
            let rate = isFilePass ? throughput(size, duration).replacingOccurrences(of: " of file", with: "") : "-"
            print("\(pad(describe(entry.pass), 24)) \(pad(Formatting.seconds(duration), 9, left: true)) \(pad(rate, 11, left: true))   \(Formatting.bytes(entry.memory))")
        }
        print("Total: \(Formatting.seconds(end - begin)); peak memory (resident): \(Formatting.bytes(ProcessMemory.peakResidentBytes()))")

        let incomplete = extract.relations.filter { !$0.isComplete }.count
        let outside = extract.nodes.filter { !box.contains($0.coordinate) }.count
        let tagged = extract.nodes.filter { !$0.tags.isEmpty }.count
        print("\nExtract")
        print("  nodes:     \(Formatting.count(extract.nodes.count)) (\(Formatting.count(tagged)) tagged, \(Formatting.count(outside)) outside the box)")
        print("  ways:      \(Formatting.count(extract.ways.count))")
        print("  relations: \(Formatting.count(extract.relations.count)) (\(Formatting.count(incomplete)) incomplete)")
        print("  nodes referenced but missing from the file: \(extract.missingNodeCount)")
        let vertices = extract.ways.reduce(0) { $0 + $1.nodeIDs.count }
        print("  way vertices: \(Formatting.count(vertices))")
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
