import FeatureStore
import FeatureStoreBuilder
import Foundation
import GeoCore
import MapStyle
import ToolSupport

extension ToolRunner {
    /// Builds the coarse levels of a set of blocks (question 50).
    ///
    /// Reads `manifest.json` in the folder, derives the files of each level with ``LevelBuilder`` and writes them to `levels/<top
    /// zoom>/`, atomically and checked with `verify()`. The manifest is written again after every block (as version 2, with the
    /// levels so far), so it only lists blocks that are complete, and a run that was stopped can be run again: a level block that
    /// is listed, whose file has the recorded size, and whose base blocks and classes are the same, is left alone.
    ///
    /// - Parameters:
    ///   - request: The folder, the levels, the number of jobs and the margin.
    ///   - progress: Called with each level block when it is done.
    /// - Returns: What was built, the size of each level and the time.
    /// - Throws: ``ToolError`` for a folder without a manifest, blocks without an overview band and bad arguments, and the errors of
    ///   building and writing.
    public static func buildLevels(_ request: LevelRequest, progress: (LevelOutcome) -> Void = { _ in }) async throws -> LevelRunReport {
        guard !request.topZooms.isEmpty, Set(request.topZooms).count == request.topZooms.count,
            request.topZooms.allSatisfy({ StoreManifest.Level.topZooms.contains($0) })
        else { throw ToolError("--levels expects different top zooms from \(StoreManifest.Level.topZooms.lowerBound) to \(StoreManifest.Level.topZooms.upperBound)") }
        guard request.margin >= 0 else { throw ToolError("--margin expects 0 or more cells") }
        let clock = ContinuousClock()
        let started = clock.now
        let directory = request.directory
        let manifestURL = directory.appendingPathComponent("manifest.json")
        var manifest: StoreManifest
        do {
            manifest = try StoreManifest(json: try Data(contentsOf: manifestURL))
        } catch {
            throw ToolError("Cannot read \(manifestURL.path): \(error). Run 'geomapkit build-region' first.")
        }
        guard manifest.bands.contains(Int(ZoomBand.overview.rawValue)) else {
            throw ToolError("The blocks hold no overview band (profile \(manifest.profile)); the levels are made from it.")
        }
        var base = manifest
        base.levels = []
        let baseBlocks = Dictionary(uniqueKeysWithValues: base.blocks.map { (LevelTile(x: $0.x, y: $0.y), $0) })
        let sourceZoom = manifest.storageZoom
        let side = 1 << sourceZoom

        // What is already there, by top zoom.
        var states: [Int: StoreManifest.Level] = Dictionary(uniqueKeysWithValues: manifest.levels.map { ($0.topZoom, $0) })
        var tasks: [LevelTask] = []
        var outcomes: [Int: LevelOutcome] = [:]
        var position = 0
        for topZoom in request.topZooms.sorted(by: >) {
            let blockZoom = min(topZoom + 2, manifest.blockZoom)
            let classes = request.style.visibleClassIDs(atZoom: Double(topZoom)).map(Int.init).sorted()
            guard let spec = try? LevelSpec(topZoom: topZoom, classes: Set(classes.map(UInt8.init))) else {
                throw ToolError("The top zoom \(topZoom) is not valid")
            }
            var level = states[topZoom]
            if let old = level, old.classes != classes || old.blockZoom != blockZoom {
                // Another class set or block size: nothing of the old level fits.
                for block in old.blocks { try? FileManager.default.removeItem(at: directory.appendingPathComponent(block.file)) }
                level = nil
            }
            var kept = Dictionary(uniqueKeysWithValues: (level?.blocks ?? []).map { (LevelTile(x: $0.x, y: $0.y), $0) })

            // The tiles of the level: the ancestors of the base blocks.
            let shift = manifest.blockZoom - blockZoom
            let tiles = Set(base.blocks.map { LevelTile(x: $0.x >> shift, y: $0.y >> shift) }).sorted { ($0.y, $0.x) < ($1.y, $1.x) }
            for stale in kept.keys where !tiles.contains(stale) {
                if let block = kept.removeValue(forKey: stale) { try? FileManager.default.removeItem(at: directory.appendingPathComponent(block.file)) }
            }
            for tile in tiles {
                // The base blocks the block reads: the cells of its tile and the margin around them.
                let cellShift = sourceZoom - blockZoom
                let columns = max(0, (tile.x << cellShift) - request.margin)...min(side - 1, ((tile.x + 1) << cellShift) - 1 + request.margin)
                let rows = max(0, (tile.y << cellShift) - request.margin)...min(side - 1, ((tile.y + 1) << cellShift) - 1 + request.margin)
                let baseShift = sourceZoom - manifest.blockZoom
                var origins: [StoreManifest.LevelBlock.Origin] = []
                for y in (rows.lowerBound >> baseShift)...(rows.upperBound >> baseShift) {
                    for x in (columns.lowerBound >> baseShift)...(columns.upperBound >> baseShift) {
                        if let block = baseBlocks[LevelTile(x: x, y: y)] { origins.append(.init(x: x, y: y, bytes: block.bytes)) }
                    }
                }
                let key = LevelTile(x: tile.x, y: tile.y)
                if let block = kept[key], block.derivedFrom == origins, fileSize(at: directory.appendingPathComponent(block.file)) == block.bytes {
                    outcomes[position] = LevelOutcome(topZoom: topZoom, x: tile.x, y: tile.y, status: .upToDate)
                    progress(outcomes[position]!)
                } else {
                    tasks.append(LevelTask(
                        position: position, spec: spec, tile: TileID(zoom: blockZoom, x: tile.x, y: tile.y)!, origins: origins,
                        hadOld: kept[key] != nil))
                    if let old = kept.removeValue(forKey: key) { try? FileManager.default.removeItem(at: directory.appendingPathComponent(old.file)) }
                }
                position += 1
            }
            states[topZoom] = StoreManifest.Level(topZoom: topZoom, blockZoom: blockZoom, classes: classes, blocks: kept.values.sorted { ($0.y, $0.x) < ($1.y, $1.x) })
        }
        func assemble() -> [StoreManifest.Level] { states.values.sorted { $0.topZoom > $1.topZoom }.filter { !$0.blocks.isEmpty } }
        manifest.levels = assemble()
        try writeManifest(manifest, to: manifestURL)

        // Build the blocks, up to `jobs` at a time.
        let jobs = max(request.jobs, 1)
        var next = 0
        let margin = request.margin
        let baseManifest = base
        try await withThrowingTaskGroup(of: BuiltLevelBlock.self) { group in
            func start() {
                guard next < tasks.count else { return }
                let task = tasks[next]
                next += 1
                group.addTask {
                    try Task.checkCancellation()
                    do {
                        return try Self.buildLevelBlock(task, base: baseManifest, directory: directory, margin: margin)
                    } catch let error as ToolError {
                        throw error
                    } catch {
                        throw ToolError("Level \(task.spec.topZoom) block \(task.tile.x)/\(task.tile.y) failed: \(error)")
                    }
                }
            }
            for _ in 0..<min(jobs, tasks.count) { start() }
            while let result = try await group.next() {
                try Task.checkCancellation()
                let task = result.task
                let topZoom = task.spec.topZoom
                if let built = result.block {
                    var level = states[topZoom] ?? StoreManifest.Level(topZoom: topZoom, blockZoom: task.tile.zoom, classes: task.spec.classes.map(Int.init).sorted())
                    level.blocks.append(StoreManifest.LevelBlock(
                        x: task.tile.x, y: task.tile.y, file: result.file, bytes: built.bytes, builtAt: Date(), derivedFrom: task.origins))
                    level.blocks.sort { ($0.y, $0.x) < ($1.y, $1.x) }
                    states[topZoom] = level
                    outcomes[task.position] = LevelOutcome(
                        topZoom: topZoom, x: task.tile.x, y: task.tile.y, status: .built(bytes: built.bytes, features: built.features, seconds: built.seconds))
                } else {
                    outcomes[task.position] = LevelOutcome(topZoom: topZoom, x: task.tile.x, y: task.tile.y, status: .empty)
                }
                manifest.levels = assemble()
                try writeManifest(manifest, to: manifestURL)
                progress(outcomes[task.position]!)
                start()
            }
        }
        let summaries = manifest.levels.filter { request.topZooms.contains($0.topZoom) }.map {
            LevelSummary(topZoom: $0.topZoom, storageZoom: $0.storageZoom, blocks: $0.blocks.count, bytes: $0.blocks.reduce(0) { $0 + $1.bytes })
        }
        return LevelRunReport(
            outcomes: outcomes.keys.sorted().compactMap { outcomes[$0] }, summaries: summaries, manifestURL: manifestURL,
            totalTime: clock.now - started, peakFootprint: ProcessMemory.peakFootprintBytes())
    }

    // MARK: Level blocks

    private struct LevelTile: Hashable { var x: Int; var y: Int }

    struct LevelTask: Sendable {
        var position: Int
        var spec: LevelSpec
        var tile: TileID
        var origins: [StoreManifest.LevelBlock.Origin]
        var hadOld: Bool
    }

    private struct BuiltLevelBlock: Sendable {
        struct Block: Sendable {
            var bytes: Int64
            var features: Int
            var seconds: Double
        }
        var task: LevelTask
        var file: String
        var block: Block?
    }

    private static func buildLevelBlock(_ task: LevelTask, base: StoreManifest, directory: URL, margin: Int) throws -> BuiltLevelBlock {
        let clock = ContinuousClock()
        let started = clock.now
        let relative = "levels/\(task.spec.topZoom)/\(task.tile.zoom)-\(task.tile.x)-\(task.tile.y).gmk"
        // A set of its own for each block, with room for the blocks that a coarse level reads in a row.
        let set = try StoreSet(manifest: base, directory: directory, maximumOpenBlocks: 32)
        guard let result = try LevelBuilder.build(from: set, spec: task.spec, tile: task.tile, margin: margin) else {
            return BuiltLevelBlock(task: task, file: relative, block: nil)
        }
        try FeatureStoreFile(data: result.data).verify()
        let target = directory.appendingPathComponent(relative)
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try result.data.write(to: target, options: .atomic)
        } catch {
            throw ToolError("Cannot write \(target.path): \(error.localizedDescription)")
        }
        let elapsed = clock.now - started
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        return BuiltLevelBlock(
            task: task, file: relative,
            block: BuiltLevelBlock.Block(bytes: Int64(result.data.count), features: result.report.featuresWritten, seconds: seconds))
    }

    private static func fileSize(at url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size].flatMap { ($0 as? Int).map(Int64.init) }
    }

    private static func writeManifest(_ manifest: StoreManifest, to url: URL) throws {
        do {
            try manifest.jsonData().write(to: url, options: .atomic)
        } catch {
            throw ToolError("Cannot write \(url.path): \(error.localizedDescription)")
        }
    }
}
