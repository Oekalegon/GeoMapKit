import FeatureStoreBuilder
import Foundation
import GeoCore
import MapBuilder
import OSMPBF
import Regions
import ToolCommands
import ToolSupport

let usage = """
GeoMapKit tools

  geomapkit scan <file.osm.pbf>
      Decode the whole file once and print counts, time and memory.

  geomapkit cut <file.osm.pbf>... (--bbox south,west,north,east | --center lat,lon --radius-km R)
                [--limit N]
      Cut an area out of the file and print the time per pass, memory and
      what the extract contains. --limit sets the relation member limit.
      Give several files for an area over a border (for example Norway and
      Sweden): they are read as one, and an object in more than one file is
      taken from the first, so list them in order of preference.

  geomapkit border-scan <file.osm.pbf>... (--bbox south,west,north,east | --center lat,lon --radius-km R) [--examples N] [--limit N]
  geomapkit border-scan --from-cache (area as above) [--cache DIR] [--allow-stale] [--examples N]
      Check the borders between countries. Cut the area, build its store in
      memory (nothing is written) and list every way of a national border
      relation (boundary=administrative, admin_level=2) in the area that is
      not stored as a border, with its tags and relations. Not a failure: a
      coastline, and the limit of the waters of one country (border_type
      territorial, eez, contiguous, in one relation only). Anything else is
      listed and the exit code is 1, so the scan can be run after a change of
      the border rules. It cannot find a border that no relation holds. Use an
      area with borders on land, in rivers and in the sea; a few degrees take
      one to four minutes and up to 9 GB for dense areas such as the Alps.

  geomapkit build <file.osm.pbf>... (--bbox south,west,north,east | --center lat,lon --radius-km R)
                  --output <file.gmk> [--profile full|watch] [--limit N]
  geomapkit build --from-cache (area as above) --output <file.gmk> [--cache DIR] [--allow-stale] [--profile full|watch]
      With --from-cache the files come from the cache (see fetch) and nothing
      is downloaded; --allow-stale uses cached files that the server has
      replaced, with a warning. The sources are recorded in <file.gmk>.sources.json.
      Cut an area, build a feature store file from it, write it atomically,
      verify it, and print times, sizes and what was stored. The default
      profile is full; watch builds the reduced Watch copy. Only whole cells
      are written, so the box is widened outward to cell borders (by less
      than one cell, about 0.044 degrees, per side) and the file covers all
      of it; the report shows the stored extent.

  geomapkit sources (--bbox south,west,north,east | --center lat,lon --radius-km R) [--cache DIR]
      Find the source files an area needs (for example Ostlandet and Sweden
      for the Halden area) and what is in the cache. Downloads nothing; it
      asks the server only small questions: the region list when the copy is
      older than 30 days, and the size of each file that is not cached. The
      default cache is GeoMapKit/Sources in the application support folder.

  geomapkit sources --region id[,id...] [--block-zoom 8] [--margin 0.1] [--cache DIR]
      The same for the blocks of regions (what build-region needs): the files
      of the regions and of the neighbours that the blocks reach into.

  geomapkit fetch (area as above | --region id[,id...]) [--cache DIR] [--yes]
      Show the same plan and, only with --yes, download the files that are
      missing or out of date. Files that were checked within 30 days are not
      asked about again. An interrupted download continues where it stopped.

  geomapkit build-region (--region id[,id...] | --tiles x/y[,x/y...] | area as above) --output <folder> [--block-zoom 8] [--jobs N] [--margin 0.1]
                         [--cache DIR] [--profile full|watch] [--rebuild] [--no-progress] [--no-open-sea]
      Build a big area (for example a country) as blocks: one store file for
      each tile of a grid (zoom 8: about 78 km), and a manifest.json that lists
      them. Each block is cut with a margin from the source files in the cache
      (nothing is downloaded; see fetch) and built on its own, up to --jobs at
      once, each using about 0.75 to 2.6 GB (dense areas). The default is half the
      cores, at most 4, and no more than the memory allows at 3 GiB each after 8 GiB
      are left free (16 GiB gives 2). The manifest is updated after each block,
      and a block that is already built from the same source files is left as it
      is, so a run that was stopped can be run again; --rebuild builds them again
      all the same (after a change of the builder that keeps the rule table, for
      the blocks of one area; the levels are built again with build-levels). --region takes the ids of
      the region index (sweden, ostlandet); the blocks that meet them are built. --tiles builds exactly
      the blocks x/y of the block zoom (with --rebuild, to do a few of them again).
      On a terminal a bar shows the blocks done, the share, the blocks running
      and, after four blocks, the time left; it is redrawn when a block starts or
      ends. --no-progress turns it off. Afterwards the sea of blocks of open sea (no coastline
      in them) is added from what their neighbours show; --no-open-sea skips that.

  geomapkit build-levels <folder> [--levels 9,8,7,6,5,4,3] [--jobs N] [--margin 32] [--rebuild]
      Add coarse levels to a set of blocks, for views of hundreds of kilometres
      (levels 9 to 3 by default)
      (the blocks hold the cells of zoom 13, which are too many to draw then).
      A level with the top zoom t serves the zooms above t-1 up to t: its cells
      have the zoom t+2, and it holds only the classes that the standard style
      shows at t, simplified for t, without what is smaller than three pixels.
      The files go to levels/<t>/ in the folder and manifest.json is written
      again (version 2) after every file. A level file is made from the blocks
      with a margin of --margin cells around it (so that a road across the
      border of a block is judged whole), and is left alone when those blocks
      and the classes are the same, so a run that was stopped can be run again;
      --rebuild builds every level block again (after the way levels are built changed).
      Each job uses memory in proportion to the area it reads (not measured for
      the coarse levels: start with --jobs 2).

  geomapkit fill-sea <folder> [--cache DIR]
      Give the blocks of a set that no source outline touches their sea. Geofabrik extracts cover every piece of
      land, so such a block is open sea; it is filled where it touches a block that shows sea. This closes the holes in
      the middle of a sea (the North Sea, the Baltic) that build-region does not see, because it only plans the blocks
      of its own area. The levels of the blocks that change are out of date: run build-levels afterwards.

  geomapkit compare <first> <second> [--limit N] [--inner N]
      Compare two stores (a .gmk file or a manifest.json) in the cells both
      hold, and list the features that differ: a check that blocks give the
      same map as one file. A store from one cut is poor at its own edge, so
      --inner N leaves out the cells within N cells of the edge of the first
      store (try 10), and says how many.

  geomapkit render <file.gmk | manifest.json> --center lat,lon --zoom Z --output <file.png> [--bearing DEGREES]
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

/// The value of an option that is a whole number in a range, or the fallback when the option is not given.
func wholeNumberOption(_ parsed: CommandLineArguments, _ name: String, _ fallback: Int, in range: ClosedRange<Int>) throws -> Int {
    guard let text = parsed.value(for: name) else { return fallback }
    guard let value = Int(text), range.contains(value) else {
        throw ToolError("--\(name) expects a whole number from \(range.lowerBound) to \(range.upperBound)")
    }
    return value
}

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
        guard !parsed.positional.isEmpty else { throw ToolError("cut needs a file") }
        let area = try AreaArgument.parse(
            bbox: parsed.value(for: "bbox"), center: parsed.value(for: "center"),
            radiusKilometres: parsed.value(for: "radius-km")
        )
        var options = AreaCutter.Options()
        if let limit = parsed.value(for: "limit") {
            guard let value = Int(limit) else { throw ToolError("--limit expects a whole number") }
            options.relationMemberLimit = value
        }
        print(ReportFormatter.text(for: try ToolRunner.cut(urls: parsed.positional.map { URL(fileURLWithPath: $0) }, area: area, options: options)))
    case "build-region":
        let parsed = try CommandLineArguments(
            rest, knownOptions: ["region", "tiles", "bbox", "center", "radius-km", "output", "block-zoom", "jobs", "margin", "cache", "profile"],
            knownFlags: ["no-progress", "rebuild", "no-open-sea"])
        guard parsed.positional.isEmpty else { throw ToolError("build-region takes an area, not files") }
        guard let output = parsed.value(for: "output"), !output.isEmpty else { throw ToolError("build-region needs --output <folder>") }
        let area: BlockRequest.Area
        if let tiles = parsed.value(for: "tiles") {
            guard parsed.value(for: "region") == nil, parsed.value(for: "bbox") == nil, parsed.value(for: "center") == nil else {
                throw ToolError("Use --tiles, --region or an area (--bbox, --center), not more than one")
            }
            let zoom = try wholeNumberOption(parsed, "block-zoom", 8, in: 0...13)
            area = .tiles(try tiles.split(separator: ",").map { text in
                let parts = text.split(separator: "/").compactMap { Int(String($0)) }
                guard parts.count == 2, let tile = TileID(zoom: zoom, x: parts[0], y: parts[1]) else {
                    throw ToolError("--tiles expects x/y,x/y (tiles of zoom \(zoom)), not '\(text)'")
                }
                return tile
            })
        } else if let regions = parsed.value(for: "region") {
            guard parsed.value(for: "bbox") == nil, parsed.value(for: "center") == nil else {
                throw ToolError("Use --region or an area (--bbox, --center), not both")
            }
            area = .regions(regions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        } else {
            area = .box(try AreaArgument.parse(
                bbox: parsed.value(for: "bbox"), center: parsed.value(for: "center"), radiusKilometres: parsed.value(for: "radius-km")))
        }
        func whole(_ name: String, _ fallback: Int, in range: ClosedRange<Int>) throws -> Int {
            try wholeNumberOption(parsed, name, fallback, in: range)
        }
        var margin = 0.1
        if let text = parsed.value(for: "margin") {
            guard let value = Double(text), (0...2).contains(value) else { throw ToolError("--margin expects degrees from 0 to 2") }
            margin = value
        }
        let defaultJobs = BlockRequest.recommendedJobs()
        let request = BlockRequest(
            area: area, output: URL(fileURLWithPath: output), blockZoom: try whole("block-zoom", 8, in: 0...13),
            jobs: try whole("jobs", defaultJobs, in: 1...64), margin: margin,
            profile: try ProfileArgument.parse(parsed.value(for: "profile")) == .watch ? .watch : .full,
            cacheDirectory: parsed.value(for: "cache").map { URL(fileURLWithPath: $0) }, rebuild: parsed.hasFlag("rebuild"),
            fillsOpenSea: !parsed.hasFlag("no-open-sea"))
        // The bar is on standard error, only when that is a terminal; the block lines stay on standard output.
        let showBar = ProgressBar.isUsableTerminal && !parsed.hasFlag("no-progress")
        func clearBar() { if showBar { FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8)) } }
        let report = try await MapBuilder.buildRegion(
            request, userAgent: ToolRunner.userAgent,
            progress: { outcome in
                clearBar()
                print(ReportFormatter.line(for: outcome, blockZoom: request.blockZoom))
                fflush(stdout)
            },
            onProgress: { state in
                guard showBar else { return }
                clearBar()
                FileHandle.standardError.write(Data(ProgressBar.line(for: state, terminalWidth: ProgressBar.terminalWidth()).utf8))
            })
        clearBar()
        print(ReportFormatter.text(for: report, blockZoom: request.blockZoom))
    case "build-levels":
        let parsed = try CommandLineArguments(rest, knownOptions: ["levels", "jobs", "margin"], knownFlags: ["rebuild"])
        guard parsed.positional.count == 1 else { throw ToolError("build-levels needs the folder of a set of blocks") }
        var topZooms = [9, 8, 7, 6, 5, 4, 3]
        if let text = parsed.value(for: "levels") {
            let values = text.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard !values.isEmpty, values.allSatisfy({ $0 != nil }) else { throw ToolError("--levels expects top zooms like 8,7,6") }
            topZooms = values.compactMap { $0 }
        }
        func whole(_ name: String, _ fallback: Int, in range: ClosedRange<Int>) throws -> Int {
            try wholeNumberOption(parsed, name, fallback, in: range)
        }
        let levelRequest = LevelRequest(
            directory: URL(fileURLWithPath: parsed.positional[0]), topZooms: topZooms, jobs: try whole("jobs", 2, in: 1...64),
            margin: try whole("margin", 32, in: 0...256), rebuild: parsed.hasFlag("rebuild"))
        let levelReport = try await MapBuilder.buildLevels(levelRequest, progress: { outcome in
            print(ReportFormatter.line(for: outcome))
            fflush(stdout)
        })
        print(ReportFormatter.text(for: levelReport))
    case "fill-sea":
        let parsed = try CommandLineArguments(rest, knownOptions: ["cache"])
        guard parsed.positional.count == 1 else { throw ToolError("fill-sea needs the folder of a set of blocks") }
        let report = try await MapBuilder.fillOpenSea(
            folder: URL(fileURLWithPath: parsed.positional[0]), cacheDirectory: parsed.value(for: "cache").map { URL(fileURLWithPath: $0) },
            userAgent: ToolRunner.userAgent)
        print("Open sea: \(report.created.count) blocks written, \(report.extended.count) blocks extended, \(report.left.count) left as they are (no neighbour shows sea).")
        for position in report.created { print("  sea block \(position.x)/\(position.y)") }
        if !report.cellsFilled.isEmpty {
            print("Cells of sea between islands: \(report.cellsFilled.values.reduce(0, +)) cells in \(report.cellsFilled.count) blocks.")
        }
    case "compare":
        let parsed = try CommandLineArguments(rest, knownOptions: ["limit", "inner"])
        guard parsed.positional.count == 2 else { throw ToolError("compare needs two stores") }
        var limit = 20, inner = 0
        if let text = parsed.value(for: "limit") {
            guard let value = Int(text), value >= 0 else { throw ToolError("--limit expects a whole number") }
            limit = value
        }
        if let text = parsed.value(for: "inner") {
            guard let value = Int(text), value >= 0 else { throw ToolError("--inner expects a whole number") }
            inner = value
        }
        print(ReportFormatter.text(for: try ToolRunner.compareStores(
            URL(fileURLWithPath: parsed.positional[0]), URL(fileURLWithPath: parsed.positional[1]), limit: limit, inner: inner)))
    case "sources", "fetch":
        let parsed = try CommandLineArguments(
            rest, knownOptions: ["bbox", "center", "radius-km", "cache", "region", "block-zoom", "margin"], knownFlags: ["yes"])
        guard parsed.positional.isEmpty else { throw ToolError("\(command) takes an area, not files") }
        let cache = parsed.value(for: "cache").map { URL(fileURLWithPath: $0) }
        let report: SourcesReport
        if let list = parsed.value(for: "region") {
            guard parsed.value(for: "bbox") == nil, parsed.value(for: "center") == nil else {
                throw ToolError("Use --region or an area (--bbox, --center), not both")
            }
            let ids = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            var blockZoom = 8
            if let text = parsed.value(for: "block-zoom") {
                guard let value = Int(text), (0...13).contains(value) else { throw ToolError("--block-zoom expects a whole number from 0 to 13") }
                blockZoom = value
            }
            var margin = 0.1
            if let text = parsed.value(for: "margin") {
                guard let value = Double(text), (0...2).contains(value) else { throw ToolError("--margin expects degrees from 0 to 2") }
                margin = value
            }
            if command == "sources" {
                report = try await ToolRunner.sources(regions: ids, blockZoom: blockZoom, margin: margin, cacheDirectory: cache)
            } else {
                let printer = ProgressPrinter()
                report = try await ToolRunner.fetch(
                    regions: ids, blockZoom: blockZoom, margin: margin, cacheDirectory: cache, confirmed: parsed.hasFlag("yes")
                ) { id, bytes, total in printer.report(id, bytes, total) }
            }
        } else {
            let area = try AreaArgument.parse(
                bbox: parsed.value(for: "bbox"), center: parsed.value(for: "center"), radiusKilometres: parsed.value(for: "radius-km"))
            if command == "sources" {
                report = try await ToolRunner.sources(area: area, cacheDirectory: cache)
            } else {
                let printer = ProgressPrinter()
                report = try await ToolRunner.fetch(area: area, cacheDirectory: cache, confirmed: parsed.hasFlag("yes")) { id, bytes, total in
                    printer.report(id, bytes, total)
                }
            }
        }
        print(ReportFormatter.text(for: report))
    case "border-scan":
        let parsed = try CommandLineArguments(
            rest, knownOptions: ["bbox", "center", "radius-km", "limit", "cache", "examples"], knownFlags: ["from-cache", "allow-stale"])
        guard parsed.hasFlag("from-cache") || !parsed.positional.isEmpty else { throw ToolError("border-scan needs a file, or --from-cache") }
        guard !(parsed.hasFlag("from-cache") && !parsed.positional.isEmpty) else {
            throw ToolError("border-scan takes files or --from-cache, not both")
        }
        let area = try AreaArgument.parse(
            bbox: parsed.value(for: "bbox"), center: parsed.value(for: "center"), radiusKilometres: parsed.value(for: "radius-km"))
        var options = AreaCutter.Options()
        if let limit = parsed.value(for: "limit") {
            guard let value = Int(limit) else { throw ToolError("--limit expects a whole number") }
            options.relationMemberLimit = value
        }
        var urls = parsed.positional.map { URL(fileURLWithPath: $0) }
        if parsed.hasFlag("from-cache") {
            let sources = try await ToolRunner.cachedSources(
                area: area, cacheDirectory: parsed.value(for: "cache").map { URL(fileURLWithPath: $0) }, allowStale: parsed.hasFlag("allow-stale"))
            for warning in sources.warnings { FileHandle.standardError.write(Data("warning: \(warning)\n".utf8)) }
            urls = sources.files
        }
        let report = try ToolRunner.borderScan(
            urls: urls, area: area, options: options, maxExamples: try wholeNumberOption(parsed, "examples", 3, in: 0...100))
        print(ReportFormatter.text(for: report))
        if !report.isClean { exit(1) }
    case "build":
        let parsed = try CommandLineArguments(
            rest, knownOptions: ["bbox", "center", "radius-km", "limit", "output", "profile", "cache"], knownFlags: ["from-cache", "allow-stale"])
        guard parsed.hasFlag("from-cache") || !parsed.positional.isEmpty else { throw ToolError("build needs a file, or --from-cache") }
        guard !(parsed.hasFlag("from-cache") && !parsed.positional.isEmpty) else {
            throw ToolError("build takes files or --from-cache, not both")
        }
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
        var urls = parsed.positional.map { URL(fileURLWithPath: $0) }
        var cached: CachedSources?
        if parsed.hasFlag("from-cache") {
            let sources = try await ToolRunner.cachedSources(
                area: area, cacheDirectory: parsed.value(for: "cache").map { URL(fileURLWithPath: $0) },
                allowStale: parsed.hasFlag("allow-stale"))
            for warning in sources.warnings { FileHandle.standardError.write(Data("warning: \(warning)\n".utf8)) }
            urls = sources.files
            cached = sources
        }
        let report = try ToolRunner.build(
            urls: urls, area: area, output: URL(fileURLWithPath: output), profile: profile, options: options)
        print(ReportFormatter.text(for: report))
        if let cached {
            try BuildSources(builtAt: Date(), area: report.cut.area, sources: cached.records).write(besides: URL(fileURLWithPath: output))
            print("Sources recorded in \(BuildSources.url(forStore: URL(fileURLWithPath: output)).lastPathComponent) (\(cached.records.map(\.regionID).joined(separator: ", "))).")
        }
    case "render":
        let parsed = try CommandLineArguments(rest, knownOptions: ["center", "zoom", "output", "size", "scale", "style", "attribution", "bearing"])
        guard let path = parsed.positional.first else { throw ToolError("render needs a store file") }
        let request = try RenderArgument.parse(
            center: parsed.value(for: "center"), zoom: parsed.value(for: "zoom"), size: parsed.value(for: "size"),
            scale: parsed.value(for: "scale"), style: parsed.value(for: "style"), output: parsed.value(for: "output"),
            attribution: parsed.value(for: "attribution"), bearing: parsed.value(for: "bearing"))
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
    // A bar that is still on the line must not run into the message.
    if ProgressBar.isUsableTerminal { FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8)) }
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}

/// Prints the progress of a download to standard error: a bar that is redrawn on a terminal, else a line for every 5 % of a file.
final class ProgressPrinter: @unchecked Sendable {
    // The download reports from one task at a time, but the lock keeps the printer safe if that ever changes.
    private let lock = NSLock()
    private var lastStep: [String: Int] = [:]
    private static let isTerminal = ProgressBar.isUsableTerminal
    private var finished = Set<String>()

    func report(_ id: String, _ bytes: Int64, _ total: Int64?) {
        lock.lock(); defer { lock.unlock() }
        guard let total, total > 0 else { return }
        if Self.isTerminal {
            // One line per file: redrawn while it comes in (at most every 1 %), then left in place.
            guard !finished.contains(id) else { return }
            let percent = Int(bytes * 100 / total)
            if bytes >= total { finished.insert(id) }
            guard percent > lastStep[id, default: -1] || bytes >= total else { return }
            lastStep[id] = percent
            FileHandle.standardError.write(Data(("\r\u{1B}[2K" + ProgressBar.downloadLine(id: id, bytes: bytes, total: total, terminalWidth: ProgressBar.terminalWidth()) + (bytes >= total ? "\n" : "")).utf8))
            return
        }
        let step = Int(bytes * 20 / total)
        guard step > lastStep[id, default: -1] else { return }
        lastStep[id] = step
        FileHandle.standardError.write(Data("\(id): \(step * 5) % (\(Formatting.bytes(bytes)) of \(Formatting.bytes(total)))\n".utf8))
    }
}
