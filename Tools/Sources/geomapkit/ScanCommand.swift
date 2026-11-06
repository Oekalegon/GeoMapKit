import Foundation
import OSMPBF
import ToolSupport

/// `geomapkit scan`: decodes a whole file once as a baseline for the other measurements.
enum ScanCommand {
    static func run(_ arguments: CommandLineArguments) throws {
        guard let path = arguments.positional.first else { throw ToolError("scan needs a file") }
        let url = URL(fileURLWithPath: path)
        let size = try fileSize(url)
        let reader = try PBFReader(url: url)
        let header = try reader.header()

        var blocks = 0, nodes = 0, ways = 0, relations = 0
        let clock = ContinuousClock()
        let elapsed = try clock.measure {
            try reader.forEachBlock { block in
                blocks += 1
                nodes += block.nodes.count
                ways += block.ways.count
                relations += block.relations.count
            }
        }
        print("File:      \(url.lastPathComponent), \(Formatting.bytes(size))")
        print("Header:    \(header.writingProgram ?? "unknown writer"), features \(header.requiredFeatures + header.optionalFeatures)")
        if let box = header.boundingBox {
            print("Header box: south \(box.south), west \(box.west), north \(box.north), east \(box.east)")
        }
        print("Objects:   \(Formatting.count(nodes)) nodes, \(Formatting.count(ways)) ways, \(Formatting.count(relations)) relations in \(Formatting.count(blocks)) blocks")
        print("Decode:    \(Formatting.seconds(elapsed)), \(throughput(size, elapsed))")
        print("Peak memory (resident): \(Formatting.bytes(ProcessMemory.peakResidentBytes()))")
    }
}
