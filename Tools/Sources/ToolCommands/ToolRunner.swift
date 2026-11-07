import Foundation
import FeatureStore
import FeatureStoreBuilder
import GeoCore
import MapRender
import MapStyle
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
        try cutExtract(url: url, area: area, options: options).report
    }

    /// Cuts an area, builds a feature store file from it, writes the file and verifies it.
    ///
    /// The output path is checked before the cut starts, so a bad path fails at once.
    ///
    /// - Parameters:
    ///   - url: The PBF file.
    ///   - area: The area to cut.
    ///   - output: Where to write the store file. The write is atomic.
    ///   - profile: The copy to build.
    ///   - options: The cutter settings.
    /// - Returns: Timings, sizes and what was stored.
    /// - Throws: ``ToolError`` for a missing input file or an unwritable output path, or whatever the cutter, builder or `FeatureStoreFile.verify()` throws.
    public static func build(
        url: URL, area: BoundingBox, output: URL, profile: BuildProfile, options: AreaCutter.Options = .init()
    ) throws -> BuildCommandReport {
        try checkWritable(output)
        let (extract, cutReport) = try cutExtract(url: url, area: area, options: options)

        let clock = ContinuousClock()
        let started = clock.now
        let result = try FeatureStoreBuilder(profile: profile).build(from: extract)
        let buildTime = clock.now - started

        // Verify before touching the output, so a bad build never replaces a good file.
        try FeatureStoreFile(data: result.data).verify()
        do {
            try result.data.write(to: output, options: .atomic)
        } catch {
            throw ToolError("Cannot write \(output.path): \(error.localizedDescription)")
        }
        // Verify again what is on disk, to catch a bad write.
        let file = try FeatureStoreFile(contentsOf: output)
        try file.verify()
        return BuildCommandReport(
            profile: profile, outputName: output.lastPathComponent, cut: cutReport, buildTime: buildTime,
            statistics: try file.statistics(), report: result.report
        )
    }

    private static func cutExtract(
        url: URL, area: BoundingBox, options: AreaCutter.Options
    ) throws -> (extract: OSMExtract, report: CutReport) {
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
        let report = CutReport(
            fileName: url.lastPathComponent, fileSize: size, area: area, passes: passes, totalTime: end - begin,
            summary: ExtractSummary(extract),
            peakFootprint: ProcessMemory.peakFootprintBytes(), peakResident: ProcessMemory.peakResidentBytes()
        )
        return (extract, report)
    }

    /// Draws a map from a feature store file into a PNG.
    ///
    /// - Parameters:
    ///   - store: The `.gmk` file.
    ///   - request: Centre, zoom, size, scale, style and output path.
    /// - Returns: What was drawn and how long it took.
    /// - Throws: ``ToolError`` for unreadable files or bad output paths, and the store or render errors.
    public static func render(store: URL, request: RenderRequest) throws -> RenderReport {
        let output = URL(fileURLWithPath: request.output)
        try checkWritable(output)
        let file: FeatureStoreFile
        do {
            file = try FeatureStoreFile(contentsOf: store)
        } catch {
            throw ToolError("Cannot read \(store.path): \(error)")
        }
        var style: MapStyle = request.style == .watch ? .watch : .standard
        if let attribution = request.attribution {
            switch attribution {
            case .full: style.attribution = .full
            case .compact: style.attribution = .compact
            case .none: style.attribution = .hidden
            }
        }
        let viewport = MapViewport(
            center: request.center, zoom: request.zoom, width: Double(request.width), height: Double(request.height))

        let clock = ContinuousClock()
        var started = clock.now
        let scene = try MapSceneBuilder(file: file, style: style).scene(for: viewport)
        let sceneTime = clock.now - started

        started = clock.now
        let png = try CoreGraphicsRenderer().pngData(for: scene, style: style, scale: request.scale)
        let drawTime = clock.now - started
        do {
            try png.write(to: output, options: .atomic)
        } catch {
            throw ToolError("Cannot write \(output.path): \(error.localizedDescription)")
        }
        let featureCount = scene.steps.filter { $0.step.part == .body }.reduce(0) {
            $0 + $1.lines.count + $1.areas.count + $1.points.count
        }
        return RenderReport(
            outputName: output.lastPathComponent, pixelWidth: Int((Double(request.width) * request.scale).rounded()),
            pixelHeight: Int((Double(request.height) * request.scale).rounded()), pngBytes: png.count, band: scene.band,
            cellCount: scene.cellCount, stepCount: scene.steps.count, featureCount: featureCount, sceneTime: sceneTime,
            drawTime: drawTime)
    }

    private static func checkWritable(_ output: URL) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: output.path, isDirectory: &isDirectory), isDirectory.boolValue {
            throw ToolError("Output path is a directory: \(output.path)")
        }
        let directory = output.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ToolError("Output directory does not exist: \(directory.path)")
        }
        guard FileManager.default.isWritableFile(atPath: directory.path) else {
            throw ToolError("Output directory is not writable: \(directory.path)")
        }
    }

    private static func fileSize(_ url: URL) throws -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { throw ToolError("No such file: \(url.path)") }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
}
