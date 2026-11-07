import FeatureStoreBuilder
import Foundation
import OSMPBF
import ToolCommands
import ToolSupport

let usage = """
GeoMapKit tools

  geomapkit scan <file.osm.pbf>
      Decode the whole file once and print counts, time and memory.

  geomapkit cut <file.osm.pbf> (--bbox south,west,north,east | --center lat,lon --radius-km R)
                [--limit N]
      Cut an area out of the file and print the time per pass, memory and
      what the extract contains. --limit sets the relation member limit.

  geomapkit build <file.osm.pbf> (--bbox south,west,north,east | --center lat,lon --radius-km R)
                  --output <file.gmk> [--profile full|watch] [--limit N]
      Cut an area, build a feature store file from it, write it atomically,
      verify it, and print times, sizes and what was stored. The default
      profile is full; watch builds the reduced Watch copy. Only whole cells
      are written, so the box is widened outward to cell borders (by less
      than one cell, about 0.044 degrees, per side) and the file covers all
      of it; the report shows the stored extent.

  geomapkit render <file.gmk> --center lat,lon --zoom Z --output <file.png>
                   [--size WxH] [--scale S] [--style standard|watch|file.json]
                   [--attribution full|compact|none]
      Draw a map from a feature store file into a PNG. Size is in points
      (default 800x600), scale is pixels per point (default 2). The data
      credit follows the style (full for standard, compact for watch);
      none leaves it off, so the app must show it elsewhere. A .json
      file as --style replaces the built-in style (see the style command).

  geomapkit inspect <file.gmk> [--class NAME] [--top N]
      Count the objects in a store file per feature class. With --class
      (for example other or path) also list the most common tags and keys
      in that class, to see what the classifier does not yet recognise.

  geomapkit style (standard|watch) --output <file.json> [--force]
      Write a built-in style as a JSON style file to start a custom style
      from. An existing file is only replaced with --force. Unknown keys and
      bad values in a style file are errors.
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
        let parsed = try CommandLineArguments(rest, knownOptions: [])
        guard let path = parsed.positional.first else { throw ToolError("scan needs a file") }
        print(ReportFormatter.text(for: try ToolRunner.scan(url: URL(fileURLWithPath: path))))
    case "cut":
        let parsed = try CommandLineArguments(rest, knownOptions: ["bbox", "center", "radius-km", "limit"])
        guard let path = parsed.positional.first else { throw ToolError("cut needs a file") }
        let area = try AreaArgument.parse(
            bbox: parsed.value(for: "bbox"), center: parsed.value(for: "center"),
            radiusKilometres: parsed.value(for: "radius-km")
        )
        var options = AreaCutter.Options()
        if let limit = parsed.value(for: "limit") {
            guard let value = Int(limit) else { throw ToolError("--limit expects a whole number") }
            options.relationMemberLimit = value
        }
        print(ReportFormatter.text(for: try ToolRunner.cut(url: URL(fileURLWithPath: path), area: area, options: options)))
    case "build":
        let parsed = try CommandLineArguments(rest, knownOptions: ["bbox", "center", "radius-km", "limit", "output", "profile"])
        guard let path = parsed.positional.first else { throw ToolError("build needs a file") }
        guard let output = parsed.value(for: "output"), !output.isEmpty else { throw ToolError("build needs --output <file.gmk>") }
        let area = try AreaArgument.parse(
            bbox: parsed.value(for: "bbox"), center: parsed.value(for: "center"),
            radiusKilometres: parsed.value(for: "radius-km")
        )
        let profile: BuildProfile = try ProfileArgument.parse(parsed.value(for: "profile")) == .watch ? .watch : .full
        var options = AreaCutter.Options()
        if let limit = parsed.value(for: "limit") {
            guard let value = Int(limit) else { throw ToolError("--limit expects a whole number") }
            options.relationMemberLimit = value
        }
        let report = try ToolRunner.build(
            url: URL(fileURLWithPath: path), area: area, output: URL(fileURLWithPath: output), profile: profile, options: options)
        print(ReportFormatter.text(for: report))
    case "render":
        let parsed = try CommandLineArguments(rest, knownOptions: ["center", "zoom", "output", "size", "scale", "style", "attribution"])
        guard let path = parsed.positional.first else { throw ToolError("render needs a store file") }
        let request = try RenderArgument.parse(
            center: parsed.value(for: "center"), zoom: parsed.value(for: "zoom"), size: parsed.value(for: "size"),
            scale: parsed.value(for: "scale"), style: parsed.value(for: "style"), output: parsed.value(for: "output"),
            attribution: parsed.value(for: "attribution"))
        print(ReportFormatter.text(for: try ToolRunner.render(store: URL(fileURLWithPath: path), request: request)))
    case "inspect":
        let parsed = try CommandLineArguments(rest, knownOptions: ["class", "top"])
        guard let path = parsed.positional.first else { throw ToolError("inspect needs a store file") }
        var top = 40
        if let value = parsed.value(for: "top") {
            guard let number = Int(value), number > 0 else { throw ToolError("--top expects a positive whole number") }
            top = number
        }
        print(ReportFormatter.text(
            for: try ToolRunner.inspect(store: URL(fileURLWithPath: path), className: parsed.value(for: "class"), top: top)))
    case "style":
        let parsed = try CommandLineArguments(rest, knownOptions: ["output"], knownFlags: ["force"])
        guard let name = parsed.positional.first else { throw ToolError("style needs standard or watch") }
        guard let output = parsed.value(for: "output"), !output.isEmpty else { throw ToolError("style needs --output <file.json>") }
        let bytes = try ToolRunner.exportStyle(name: name, output: URL(fileURLWithPath: output), overwrite: parsed.hasFlag("force"))
        print("Wrote \(name) style to \(output) (\(bytes) bytes)")
    case "help", "--help", "-h":
        print(usage)
    default:
        throw ToolError("Unknown command '\(command)'\n\n\(usage)")
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
