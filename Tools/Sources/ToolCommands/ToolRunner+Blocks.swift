import FeatureStore
import FeatureStoreBuilder
import Foundation
import GeoCore
import OSMPBF
import Regions
import ToolSupport

extension ToolRunner {
    /// Builds a big area as blocks: one store file for each tile of a coarse grid, and a manifest that lists them.
    ///
    /// Each block is built on its own: its area is cut, with a margin, from the source files its tile needs, and only the cells of
    /// the tile are written. Up to `jobs` blocks are built at once. The source files must be in the cache (see `fetch`); nothing
    /// is downloaded. A block that is already in the manifest, built from the same source files, is left as it is, so a run that
    /// was stopped can be run again. The manifest is written after each block, so it lists only blocks that are complete.
    ///
    /// - Parameters:
    ///   - request: What to build.
    ///   - catalog: The list of regions, or `nil` for the Geofabrik index kept in the cache folder.
    ///   - downloader: The network for the region index, or `nil` for `URLSession`.
    ///   - progress: Called when a block is done, from the calling task.
    /// - Returns: The report.
    /// - Throws: ``ToolError`` for a bad request, an unknown region or source files that are not in the cache; the errors of the
    ///   cutter, the builder and the files; `CancellationError`.
    public static func buildRegion(
        _ request: BlockRequest, catalog: (any RegionCatalog)? = nil, downloader: (any Downloader)? = nil,
        progress: (BlockOutcome) -> Void = { _ in }
    ) async throws -> BlockRunReport {
        guard (0...13).contains(request.blockZoom) else { throw ToolError("--block-zoom must be from 0 to 13") }
        guard request.margin >= 0, request.margin <= 2, request.margin.isFinite else { throw ToolError("--margin must be from 0 to 2 degrees") }
        let clock = ContinuousClock()
        let started = clock.now
        let cacheDirectory = try request.cacheDirectory ?? SourceCache.defaultDirectory()
        let index = try await (catalog ?? GeofabrikCatalog(
            directory: cacheDirectory, downloader: downloader ?? URLSessionDownloader(userAgent: userAgent))).index()
        let cache = SourceCache(directory: cacheDirectory)

        // The blocks of the area, and for each the box to cut and the regions whose files it needs.
        var tasks: [BlockTask] = []
        var outcomes: [Int: BlockOutcome] = [:]
        var needed: [String: SourceRegion] = [:]
        let tiles = try blockTiles(for: request, in: index)
        for (position, tile) in tiles.enumerated() {
            let box = cutBox(of: tile, margin: request.margin)
            let regions = index.regions(covering: box).regions
            if regions.isEmpty {
                outcomes[position] = BlockOutcome(x: tile.x, y: tile.y, status: .empty, regions: [])
            } else {
                for region in regions { needed[region.id] = region }
                tasks.append(BlockTask(position: position, tile: tile, cutBox: box, regions: regions))
            }
        }
        guard !tasks.isEmpty else { throw ToolError("No source region covers this area.") }

        // Every source file has to be in the cache already.
        var warnings: [String] = []
        var records: [String: CachedSource] = [:]
        var missing: [String] = []
        for region in needed.values.sorted(by: { $0.id < $1.id }) {
            let (status, record) = cache.status(ofRegionID: region.id)
            switch status {
            case .current: records[region.id] = record
            case .stale:
                records[region.id] = record
                warnings.append("\(region.name) was last checked more than 30 days ago; run 'geomapkit sources' to see whether it has changed.")
            case .missing, .damaged: missing.append("\(region.name) (\(region.id))")
            }
        }
        guard missing.isEmpty else {
            throw ToolError(
                "These source files are not in the cache: \(missing.joined(separator: ", ")). Run 'geomapkit fetch' for the area first (--region or --bbox, with --yes).")
        }

        let blocksFolder = request.output.appendingPathComponent("blocks", isDirectory: true)
        let manifestURL = request.output.appendingPathComponent("manifest.json")
        do {
            try FileManager.default.createDirectory(at: blocksFolder, withIntermediateDirectories: true)
        } catch {
            throw ToolError("Cannot create \(blocksFolder.path): \(error.localizedDescription)")
        }

        // Blocks from an earlier run that fit this one are kept; a manifest of another build is started again.
        let profileName = request.profile == .watch ? "watch" : "full"
        var manifest = existingManifest(at: manifestURL, blockZoom: request.blockZoom, profile: profileName)
        if manifest == nil, FileManager.default.fileExists(atPath: manifestURL.path) {
            // The manifest of another build is not reused, and it must not stay as if it were the result of this run.
            try? FileManager.default.removeItem(at: manifestURL)
        }
        var kept = Dictionary(uniqueKeysWithValues: (manifest?.blocks ?? []).map { (BlockKey(x: $0.x, y: $0.y), $0) })
        var toBuild: [BlockTask] = []
        for task in tasks {
            let sources = task.regions.compactMap { records[$0.id] }
            let key = BlockKey(x: task.tile.x, y: task.tile.y)
            if let block = kept[key], blockIsUpToDate(block, sources: sources, folder: request.output) {
                let outcome = BlockOutcome(x: task.tile.x, y: task.tile.y, status: .upToDate, regions: task.regions.map(\.id))
                outcomes[task.position] = outcome
                progress(outcome)
            } else {
                kept[key] = nil
                toBuild.append(task)
            }
        }

        // Build the blocks, up to `jobs` at a time.
        let jobs = max(request.jobs, 1)
        var next = 0
        var built = 0
        try await withThrowingTaskGroup(of: BuiltBlock.self) { group in
            func start() {
                guard next < toBuild.count else { return }
                let task = toBuild[next]
                next += 1
                let files = task.regions.map { cache.fileURL(forRegionID: $0.id) }
                let sources = task.regions.compactMap { records[$0.id] }
                let profile = request.profile
                let target = blocksFolder.appendingPathComponent("\(request.blockZoom)-\(task.tile.x)-\(task.tile.y).gmk")
                group.addTask {
                    try Task.checkCancellation()
                    return try Self.buildBlock(task, files: files, sources: sources, profile: profile, target: target)
                }
            }
            for _ in 0..<min(jobs, toBuild.count) { start() }
            while let result = try await group.next() {
                try Task.checkCancellation()
                let task = result.task
                let regionIDs = task.regions.map(\.id)
                if let block = result.block {
                    kept[BlockKey(x: task.tile.x, y: task.tile.y)] = StoreManifest.Block(
                        x: task.tile.x, y: task.tile.y, file: "blocks/\(result.fileName)", bytes: block.bytes, builtAt: Date(),
                        sources: block.sources)
                    if manifest == nil {
                        manifest = StoreManifest(
                            formatVersion: block.formatVersion, classifierVersion: block.classifierVersion, storageZoom: block.storageZoom,
                            blockZoom: request.blockZoom, bands: block.bands, profile: profileName,
                            attribution: block.attribution, blocks: [])
                    }
                    manifest?.blocks = kept.values.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
                    if let manifest { try Self.write(manifest, to: manifestURL) }
                    built += 1
                    let outcome = BlockOutcome(
                        x: task.tile.x, y: task.tile.y, status: .built(bytes: block.bytes, cells: block.cells, seconds: block.seconds),
                        regions: regionIDs)
                    outcomes[task.position] = outcome
                    progress(outcome)
                } else {
                    let outcome = BlockOutcome(x: task.tile.x, y: task.tile.y, status: .empty, regions: regionIDs)
                    outcomes[task.position] = outcome
                    progress(outcome)
                }
                start()
            }
        }
        // A manifest that exists after a run in which nothing was built (everything up to date, or empty) is the one that was there.
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ToolError("Nothing was built: every block of this area is empty.")
        }
        return BlockRunReport(
            outcomes: outcomes.keys.sorted().compactMap { outcomes[$0] }, manifestURL: manifestURL, totalTime: clock.now - started,
            peakFootprint: ProcessMemory.peakFootprintBytes(), warnings: warnings)
    }

    // MARK: Blocks

    private struct BlockKey: Hashable { var x: Int; var y: Int }

    private struct BlockTask: Sendable {
        var position: Int
        var tile: TileID
        var cutBox: BoundingBox
        var regions: [SourceRegion]
    }

    private struct BuiltBlock: Sendable {
        struct Block: Sendable {
            var bytes: Int64
            var cells: Int
            var seconds: Double
            var sources: [StoreManifest.Source]
            var formatVersion: Int
            var classifierVersion: Int
            var storageZoom: Int
            var bands: [ZoomBand]
            var attribution: String
        }
        var task: BlockTask
        var fileName: String
        /// `nil` when the cut had no cell to store.
        var block: Block?
    }

    /// The tiles of the block grid that the request covers, in order of row and column.
    private static func blockTiles(for request: BlockRequest, in index: RegionIndex) throws -> [TileID] {
        let zoom = request.blockZoom
        let box: BoundingBox
        var named: [SourceRegion] = []
        switch request.area {
        case .box(let area):
            guard area.isValid else { throw ToolError("The area is not valid") }
            box = area
        case .regions(let ids):
            guard !ids.isEmpty else { throw ToolError("--region needs at least one region id") }
            for id in ids {
                guard let region = index.region(withID: id) else {
                    throw ToolError("The region index has no region '\(id)'. Run 'geomapkit sources' with an area to see the ids of the regions.")
                }
                named.append(region)
            }
            box = BoundingBox(
                south: named.map(\.boundingBox.south).min() ?? 0, west: named.map(\.boundingBox.west).min() ?? 0,
                north: named.map(\.boundingBox.north).max() ?? 0, east: named.map(\.boundingBox.east).max() ?? 0)
        }
        guard let northWest = TileID.containing(Coordinate(latitude: min(box.north, TileID.maximumLatitude), longitude: box.west), zoom: zoom),
            let southEast = TileID.containing(Coordinate(latitude: max(box.south, -TileID.maximumLatitude), longitude: min(box.east, 179.999999)), zoom: zoom)
        else { throw ToolError("The area is not valid") }
        var tiles: [TileID] = []
        for y in northWest.y...southEast.y {
            for x in northWest.x...southEast.x {
                guard let tile = TileID(zoom: zoom, x: x, y: y) else { continue }
                if !named.isEmpty {
                    // A tile belongs to the region when at least one of a grid of points in it lies inside an outline.
                    let tileBox = Self.tileBox(tile)
                    var inside = false
                    let side = 8
                    search: for row in 0..<side {
                        for column in 0..<side {
                            let point = Coordinate(
                                latitude: tileBox.south + (tileBox.north - tileBox.south) * (Double(row) + 0.5) / Double(side),
                                longitude: tileBox.west + (tileBox.east - tileBox.west) * (Double(column) + 0.5) / Double(side))
                            if named.contains(where: { $0.contains(point) }) { inside = true; break search }
                        }
                    }
                    if !inside { continue }
                }
                tiles.append(tile)
            }
        }
        guard !tiles.isEmpty else { throw ToolError("No block lies in this area.") }
        return tiles
    }

    private static func tileBox(_ tile: TileID) -> BoundingBox {
        BoundingBox(
            south: tile.southEast.latitude, west: tile.northWest.longitude, north: tile.northWest.latitude, east: tile.southEast.longitude)
    }

    /// The box that is cut for a block: the tile and a margin on every side.
    private static func cutBox(of tile: TileID, margin: Double) -> BoundingBox {
        let box = tileBox(tile)
        return BoundingBox(
            south: max(box.south - margin, -TileID.maximumLatitude), west: max(box.west - margin, -180),
            north: min(box.north + margin, TileID.maximumLatitude), east: min(box.east + margin, 180))
    }

    private static func existingManifest(at url: URL, blockZoom: Int, profile: String) -> StoreManifest? {
        guard let data = try? Data(contentsOf: url), let manifest = try? StoreManifest(json: data) else { return nil }
        guard manifest.blockZoom == blockZoom, manifest.profile == profile, manifest.storageZoom == FeatureStoreBuilder.storageZoom,
            manifest.classifierVersion == Int(FeatureClassifier.version)
        else { return nil }
        return manifest
    }

    private static func blockIsUpToDate(_ block: StoreManifest.Block, sources: [CachedSource], folder: URL) -> Bool {
        let file = folder.appendingPathComponent(block.file)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int, Int64(size) == block.bytes else { return false }
        guard block.sources.count == sources.count else { return false }
        return zip(block.sources, sources).allSatisfy { $0.regionID == $1.regionID && $0.size == $1.size && $0.etag == $1.etag && $0.lastModified == $1.lastModified }
    }

    /// Cuts and builds one block and writes its file. Runs on any thread; holds the cut in memory while it runs.
    private static func buildBlock(
        _ task: BlockTask, files: [URL], sources: [CachedSource], profile: BuildProfile, target: URL
    ) throws -> BuiltBlock {
        let clock = ContinuousClock()
        let started = clock.now
        let readers = try files.map { try PBFReader(url: $0) }
        let extract = try AreaCutter().cut(readers, to: task.cutBox)
        let writeBox = FeatureStoreBuilder.cellAlignedBox(covering: tileBox(task.tile))
        let result = try FeatureStoreBuilder(profile: profile).build(from: extract, writing: writeBox)
        let file = try FeatureStoreFile(data: result.data)
        let name = target.lastPathComponent
        guard file.cellCount > 0 else { return BuiltBlock(task: task, fileName: name, block: nil) }
        try file.verify()
        do {
            try result.data.write(to: target, options: .atomic)
        } catch {
            throw ToolError("Cannot write \(target.path): \(error.localizedDescription)")
        }
        let seconds = Double((clock.now - started).components.seconds) + Double((clock.now - started).components.attoseconds) / 1e18
        return BuiltBlock(
            task: task, fileName: name,
            block: BuiltBlock.Block(
                bytes: Int64(result.data.count), cells: file.cellCount, seconds: seconds,
                sources: sources.map {
                    StoreManifest.Source(
                        regionID: $0.regionID, url: $0.url.absoluteString, size: $0.size, downloadedAt: $0.downloadedAt, etag: $0.etag,
                        lastModified: $0.lastModified)
                },
                formatVersion: file.formatVersion, classifierVersion: file.classifierVersion, storageZoom: file.storageZoom,
                bands: file.bands, attribution: file.attribution))
    }

    private static func write(_ manifest: StoreManifest, to url: URL) throws {
        do {
            try manifest.jsonData().write(to: url, options: .atomic)
        } catch {
            throw ToolError("Cannot write \(url.path): \(error.localizedDescription)")
        }
    }
}
