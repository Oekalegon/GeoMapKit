import Foundation
import ToolSupport

let usage = """
GeoMapKit tools

  geomapkit scan <file.osm.pbf>
      Decode the whole file once and print counts, time and memory.

  geomapkit cut <file.osm.pbf> (--bbox south,west,north,east | --center lat,lon --radius-km R)
                [--limit N]
      Cut an area out of the file and print the time per pass, memory and
      what the extract contains. --limit sets the relation member limit.
"""

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
        print(usage)
        exit(0)
    }
    let rest = Array(arguments.dropFirst())
    switch command {
    case "scan":
        try ScanCommand.run(try CommandLineArguments(rest, knownOptions: []))
    case "cut":
        try CutCommand.run(try CommandLineArguments(rest, knownOptions: ["bbox", "center", "radius-km", "limit"]))
    case "help", "--help", "-h":
        print(usage)
    default:
        throw ToolError("Unknown command '\(command)'\n\n\(usage)")
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
