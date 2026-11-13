import FeatureStore
import FeatureStoreBuilder
import Foundation
import GeoCore
import OSMPBF
import Regions


extension MapBuilder {
    /// Builds a big area as blocks: one store file for each tile of a coarse grid, and a manifest that lists them.
    ///
    /// Each block is built on its own: its area is cut, with a margin, from the source files its tile needs, and only the cells of
    /// the tile are written. Up to `jobs` blocks are built at once. The source files must be in the cache (see `fetch`); nothing
    /// is downloaded. A block that is already in the manifest, built from the same source files, is left as it is, so a run that
    /// was stopped can be run again. The manifest is written after each block, so it lists only blocks that are complete. When the
    /// blocks are done, the sea of blocks of open sea is added from what their neighbours show (`OpenSea`, question 53) unless
    /// ``BlockRequest/fillsOpenSea`` is off.
    ///
    /// - Parameters:
    ///   - request: What to build.
    ///   - catalog: The list of regions, or `nil` for the Geofabrik index kept in the cache folder.
    ///   - downloader: The network for the region index, or `nil` for `URLSession`.
    ///   - userAgent: The user agent of that `URLSession`; an app passes its own name.
    ///   - progress: Called when a block is done, from the calling task.
    ///   - onProgress: Called with the state of the whole run when it starts, whenever a block starts and whenever one is done, from the
    ///     calling task. A progress bar is drawn from it.
    /// - Returns: The report.
    /// - Throws: ``MapBuilderError`` for a bad request, an unknown region or source files that are not in the cache; the errors of the
    ///   cutter, the builder and the files; `CancellationError`.
    public static func buildRegion(
        _ request: BlockRequest, catalog: (any RegionCatalog)? = nil, downloader: (any Downloader)? = nil, userAgent: String = MapBuilder.defaultUserAgent,
        progress: (BlockOutcome) -> Void = { _ in }, onProgress: (BlockProgress) -> Void = { _ in }
    ) async throws -> BlockRunReport {
        guard (0...13).contains(request.blockZoom) else { throw MapBuilderError("The block zoom must be from 0 to 13") }
        guard request.margin >= 0, request.margin <= 2, request.margin.isFinite else { throw MapBuilderError("The margin must be from 0 to 2 degrees") }
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
        for planned in try plannedBlocks(area: request.area, blockZoom: request.blockZoom, margin: request.margin, in: index) {
            if planned.regions.isEmpty {
                outcomes[planned.position] = BlockOutcome(x: planned.tile.x, y: planned.tile.y, status: .empty, regions: [])
            } else {
                for region in planned.regions { needed[region.id] = region }
                tasks.append(planned)
            }
        }
        guard !tasks.isEmpty else { throw MapBuilderError("No source region covers this area.") }

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
                warnings.append("\(region.name) was last checked more than 30 days ago; check whether it has changed.")
            case .missing, .damaged:
                let parent = region.parentID.flatMap { index.region(withID: $0)?.name }.map { " in \($0)" } ?? ""
                missing.append("\(region.name)\(parent) (\(region.id))")
            }
        }
        guard missing.isEmpty else {
            throw MapBuilderError(
                "These source files are not in the cache: \(missing.joined(separator: ", ")). Download them first.")
        }

        let blocksFolder = request.output.appendingPathComponent("blocks", isDirectory: true)
        let manifestURL = request.output.appendingPathComponent("manifest.json")
        do {
            try FileManager.default.createDirectory(at: blocksFolder, withIntermediateDirectories: true)
        } catch {
            throw MapBuilderError("Cannot create \(blocksFolder.path): \(error.localizedDescription)")
        }

        // Blocks from an earlier run that fit this one are kept; a manifest of another build is started again.
        let profileName = request.profile == .watch ? "watch" : "full"
        var manifest = existingManifest(at: manifestURL, blockZoom: request.blockZoom, profile: profileName)
        let existingManifestWasDiscarded = manifest == nil && FileManager.default.fileExists(atPath: manifestURL.path)
        if existingManifestWasDiscarded {
            // The manifest of another build is not reused, and it must not stay as if it were the result of this run.
            try? FileManager.default.removeItem(at: manifestURL)
        }
        var kept = Dictionary(uniqueKeysWithValues: (manifest?.blocks ?? []).map { (BlockKey(x: $0.x, y: $0.y), $0) })
        var toBuild: [BlockTask] = []
        var finishedCount = 0
        var removedFiles: [BlockKey: String] = [:]
        for task in tasks {
            let sources = task.regions.compactMap { records[$0.id] }
            let key = BlockKey(x: task.tile.x, y: task.tile.y)
            if !request.rebuild, let block = kept[key], blockIsUpToDate(block, sources: sources, folder: request.output) {
                let outcome = BlockOutcome(x: task.tile.x, y: task.tile.y, status: .upToDate, regions: task.regions.map(\.id))
                outcomes[task.position] = outcome
                finishedCount += 1
                progress(outcome)
            } else {
                if let old = kept[key] { removedFiles[key] = old.file }
                kept[key] = nil
                toBuild.append(task)
            }
        }

        // A block that is built again (or that goes) makes every level that read it out of date, so the levels go (build-levels makes
        // them again); a manifest that lists them would show levels that do not match the blocks. A tile that has nothing to store is
        // looked at again in every run and changes nothing, so it does not count.
        var levelsDropped = false
        func dropLevels() throws {
            guard !levelsDropped else { return }
            levelsDropped = true
            try? FileManager.default.removeItem(at: request.output.appendingPathComponent("levels", isDirectory: true))
            if var current = manifest, !current.levels.isEmpty {
                current.levels = []
                manifest = current
                try Self.write(current, to: manifestURL)
            }
        }
        // The levels of a manifest that was not reused are not reused either.
        if existingManifestWasDiscarded { try dropLevels() }

        // Build the blocks, up to `jobs` at a time.
        let jobs = max(request.jobs, 1)
        var next = 0
        var built = 0
        var running = 0
        let buildStart = clock.now
        let total = tasks.count
        let finishedAtStart = finishedCount
        func state() -> BlockProgress {
            let elapsed = clock.now - buildStart
            return BlockProgress(
                total: total, finished: finishedCount, running: running, built: built, elapsed: elapsed,
                remaining: BlockProgress.estimateRemaining(
                    left: total - finishedCount, finishedInRun: finishedCount - finishedAtStart, elapsed: elapsed))
        }
        onProgress(state())
        try await withThrowingTaskGroup(of: BuiltBlock.self) { group in
            func start() {
                guard next < toBuild.count else { return }
                let task = toBuild[next]
                next += 1
                running += 1
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
            onProgress(state())
            while let result = try await group.next() {
                try Task.checkCancellation()
                running -= 1
                finishedCount += 1
                let task = result.task
                let regionIDs = task.regions.map(\.id)
                if let block = result.block {
                    try dropLevels()
                    kept[BlockKey(x: task.tile.x, y: task.tile.y)] = StoreManifest.Block(
                        x: task.tile.x, y: task.tile.y, file: "blocks/\(result.fileName)", bytes: block.bytes, builtAt: Date(),
                        sources: block.sources)
                    if manifest == nil {
                        manifest = StoreManifest(
                            formatVersion: block.formatVersion, classifierVersion: block.classifierVersion, storageZoom: block.storageZoom,
                            blockZoom: request.blockZoom, bands: Self.bands(of: request.profile), profile: profileName,
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
                    // The block has nothing to store now: its old entry and file go, and the manifest says so.
                    if let old = removedFiles[BlockKey(x: task.tile.x, y: task.tile.y)] {
                        try dropLevels()
                        try? FileManager.default.removeItem(at: request.output.appendingPathComponent(old))
                        if manifest != nil {
                            manifest?.blocks = kept.values.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
                            if let manifest { try Self.write(manifest, to: manifestURL) }
                        }
                    }
                    let outcome = BlockOutcome(x: task.tile.x, y: task.tile.y, status: .empty, regions: regionIDs)
                    outcomes[task.position] = outcome
                    progress(outcome)
                }
                start()
                onProgress(state())
            }
        }
        // Open sea has no coastline in its cut and so no sea of its own: it is filled from what its neighbours show (question 53). The
        // blocks it adds or changes are not in the levels that exist, which build-levels finds by comparing the blocks they came from.
        var openSea: OpenSea.Report?
        if profileName == "full", request.fillsOpenSea, let current = manifest {
            var covered: [OpenSea.Position: [StoreManifest.Source]] = [:]
            // The outlines of the source files stop at the territorial sea, so a block of open sea is mostly outside them (8/139/80 is 10%
            // covered): any coverage counts, none is unknown.
            for task in tasks where task.coveredShare > 0 {
                covered[OpenSea.Position(x: task.tile.x, y: task.tile.y)] = task.regions.compactMap { records[$0.id] }.map {
                    StoreManifest.Source(
                        regionID: $0.regionID, url: $0.url.absoluteString, size: $0.size, downloadedAt: $0.downloadedAt, etag: $0.etag,
                        lastModified: $0.lastModified)
                }
            }
            let (filled, report) = try OpenSea.fill(manifest: current, folder: request.output, covered: covered) { updated in
                try Self.write(updated, to: manifestURL)
            }
            if report.changed { manifest = filled }
            openSea = report
        }
        // A manifest that exists after a run in which nothing was built (everything up to date, or empty) is the one that was there.
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw MapBuilderError("Nothing was built: every block of this area is empty.")
        }
        return BlockRunReport(
            outcomes: outcomes.keys.sorted().compactMap { outcomes[$0] }, manifestURL: manifestURL, totalTime: clock.now - started,
            peakFootprint: ProcessMemory.peakFootprintBytes(), warnings: warnings, openSea: openSea)
    }

    // MARK: Blocks

    private struct BlockKey: Hashable { var x: Int; var y: Int }

    /// One block of a plan (``plannedBlocks(area:blockZoom:margin:in:)``): which tile, which box is cut and which regions are needed.
    public struct BlockTask: Sendable {
        /// The place of the block in the plan, counted from 0 in the order of the tiles.
        public let position: Int
        /// The tile of the block, at the block zoom.
        public let tile: TileID
        /// The box that is cut for the block, in degrees: the tile plus the margin.
        public let cutBox: BoundingBox
        /// The regions whose source files the cut needs; empty when no region covers the block.
        public let regions: [SourceRegion]
        /// The share of the tile (not the cut) that the outlines of the regions cover; 0 when no source file has data there.
        public internal(set) var coveredShare: Double = 0
    }

    /// The blocks of an area with, for each, the box that is cut and the regions whose files it needs (none if no region covers it).
    public static func plannedBlocks(area: BlockRequest.Area, blockZoom: Int, margin: Double, in index: RegionIndex) throws -> [BlockTask] {
        try blockTiles(for: area, blockZoom: blockZoom, in: index).enumerated().map { position, tile in
            let box = cutBox(of: tile, margin: margin)
            // The tile alone decides whether the data there is known: the margin only reaches into the next block.
            let share = index.regions(covering: tileBox(tile), samplesPerSide: 16).coveredShare
            return BlockTask(position: position, tile: tile, cutBox: box, regions: index.regions(covering: box).regions, coveredShare: share)
        }
    }

    /// The source regions whose files a build of an area reads: the regions of its blocks, neighbours across a border included
    /// (a block is cut with a margin, so a block at the border needs the file on the other side).
    ///
    /// This is the same answer the build uses, so downloading these files means ``buildRegion(_:catalog:downloader:userAgent:progress:onProgress:)``
    /// finds them in the cache.
    ///
    /// - Parameters:
    ///   - area: The area.
    ///   - blockZoom: The zoom of the block grid.
    ///   - margin: The margin of the cut, in degrees.
    ///   - index: The region index.
    /// - Returns: The regions, sorted by id; empty when no region covers the area.
    /// - Throws: ``MapBuilderError`` for an area that is invalid, too large or names an unknown region.
    public static func requiredRegions(area: BlockRequest.Area, blockZoom: Int = 8, margin: Double = 0.1, in index: RegionIndex) throws -> [SourceRegion] {
        var found: [String: SourceRegion] = [:]
        for task in try plannedBlocks(area: area, blockZoom: blockZoom, margin: margin, in: index) {
            for region in task.regions { found[region.id] = region }
        }
        return found.values.sorted { $0.id < $1.id }
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
    private static func blockTiles(for area: BlockRequest.Area, blockZoom zoom: Int, in index: RegionIndex) throws -> [TileID] {
        let box: BoundingBox
        var named: [SourceRegion] = []
        switch area {
        case .tiles(let tiles):
            guard !tiles.isEmpty else { throw MapBuilderError("At least one tile is needed") }
            guard let other = tiles.first(where: { $0.zoom != zoom }) else { return tiles }
            throw MapBuilderError("The tiles must be tiles of the block zoom (\(zoom)); \(other.zoom)/\(other.x)/\(other.y) is not one")
        case .box(let area):
            guard area.isValid else { throw MapBuilderError("The area is not valid") }
            box = area
        case .regions(let ids):
            guard !ids.isEmpty else { throw MapBuilderError("At least one region id is needed") }
            for id in ids {
                guard let region = index.region(withID: id) else {
                    throw MapBuilderError("The region index has no region '\(id)'. Look up the ids of the regions in the region index.")
                }
                named.append(region)
            }
            box = BoundingBox(
                south: named.map(\.boundingBox.south).min() ?? 0, west: named.map(\.boundingBox.west).min() ?? 0,
                north: named.map(\.boundingBox.north).max() ?? 0, east: named.map(\.boundingBox.east).max() ?? 0)
        }
        // A box this large at this zoom would be thousands of blocks; the regions of the whole world are not what this is for.
        let columnsAcross = (box.east - box.west) / 360 * Double(1 << zoom)
        guard columnsAcross < 1_000, (box.north - box.south) / 170 * Double(1 << zoom) < 1_000 else {
            throw MapBuilderError("This area is too large for blocks of zoom \(zoom): use a smaller area or a lower block zoom.")
        }
        guard let northWest = TileID.containing(Coordinate(latitude: min(box.north, TileID.maximumLatitude), longitude: box.west), zoom: zoom),
            let southEast = TileID.containing(Coordinate(latitude: max(box.south, -TileID.maximumLatitude), longitude: min(box.east, 179.999999)), zoom: zoom)
        else { throw MapBuilderError("The area is not valid") }
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
        guard !tiles.isEmpty else { throw MapBuilderError("No block lies in this area.") }
        guard tiles.count <= 2_000 else {
            throw MapBuilderError("This area is \(tiles.count) blocks of zoom \(zoom); the limit is 2,000. Use a smaller area or a lower block zoom.")
        }
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

    /// The bands the blocks of a profile can hold. A block file only has the bands that hold a feature, so the manifest must not take
    /// them from the first block that happens to be built (a block of sea may have one band).
    private static func bands(of profile: BuildProfile) -> [ZoomBand] {
        profile == .watch ? [.mid, .detail] : [.overview, .mid, .detail]
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
            throw MapBuilderError("Cannot write \(target.path): \(error.localizedDescription)")
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

    static func write(_ manifest: StoreManifest, to url: URL) throws {
        do {
            try manifest.jsonData().write(to: url, options: .atomic)
        } catch {
            throw MapBuilderError("Cannot write \(url.path): \(error.localizedDescription)")
        }
    }
}
