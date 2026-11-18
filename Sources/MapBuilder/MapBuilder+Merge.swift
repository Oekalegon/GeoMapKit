import FeatureStore
import Foundation

extension MapBuilder {
    /// Merges maps: the blocks of the maps are put in one map, and for a tile that more than one has, the larger block is kept.
    ///
    /// The maps must agree on the format of their blocks (the format and rule versions, the zooms, the bands and the profile); a block is
    /// not opened or changed, only copied (on a volume that clones files the copy takes no extra space). The levels are not merged:
    /// a new map has none, and a map that others are added to keeps its own, so ``buildLevels(_:progress:onProgress:)`` builds the levels
    /// of the tiles that changed. After a merge the sea between the maps is filled by ``fillOpenSea(folder:cacheDirectory:catalog:downloader:userAgent:)``.
    ///
    /// Do not merge into a map while it is being built: the build writes its own manifest and would drop the merged blocks. A merge that
    /// stops leaves either the map as it was (the manifest is written last) or the merged map; files that the manifest does not list may be left.
    ///
    /// - Parameters:
    ///   - request: The maps and the output.
    ///   - progress: Called after each block is written, with the number written and the number to write.
    /// - Returns: The report.
    /// - Throws: ``MapBuilderError`` for a map that has no manifest, blocks that are missing or do not have the size the manifest says,
    ///   maps that do not agree, or an output that is in use; `CancellationError`.
    public static func mergeMaps(_ request: MapMergeRequest, progress: (Int, Int) -> Void = { _, _ in }) async throws -> MapMergeReport {
        let fileManager = FileManager.default
        let inputs = request.inputs.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        let output = request.output.standardizedFileURL.resolvingSymlinksInPath()
        guard Set(inputs.map(\.path)).count == inputs.count else { throw MapBuilderError("The same map is listed twice") }
        let inPlace = inputs.firstIndex { $0.path == output.path }
        guard inputs.count >= 2 else { throw MapBuilderError("A merge needs at least two maps") }

        // Read and compare the manifests.
        var manifests: [StoreManifest] = []
        for folder in inputs {
            let url = folder.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: url) else { throw MapBuilderError("\(folder.lastPathComponent) has no manifest.json: it is not a map") }
            do { manifests.append(try StoreManifest(json: data)) } catch { throw MapBuilderError("The manifest of \(folder.lastPathComponent) cannot be used: \(error)") }
        }
        let first = manifests[0]
        for (index, manifest) in manifests.enumerated().dropFirst() {
            if let difference = Self.difference(first, manifest) {
                throw MapBuilderError("\(inputs[index].lastPathComponent) cannot be merged with \(inputs[0].lastPathComponent): \(difference)")
            }
        }

        // The output.
        if inPlace == nil {
            var isFolder: ObjCBool = false
            if fileManager.fileExists(atPath: output.path, isDirectory: &isFolder) {
                let content = isFolder.boolValue ? (try? fileManager.contentsOfDirectory(atPath: output.path)) ?? ["?"] : ["?"]
                guard content.isEmpty else {
                    throw MapBuilderError("\(output.path) exists and is not empty. Merge into a new folder, or name one of the maps as the output to add the others to it.")
                }
            }
        }

        // For each tile, the blocks the maps have; the larger one is kept, and the map that is added to wins a tie (nothing to write then).
        struct Candidate { var map: Int; var block: StoreManifest.Block }
        var tiles: [Int: [Candidate]] = [:]
        let side = 1 << first.blockZoom
        for (map, manifest) in manifests.enumerated() {
            for block in manifest.blocks { tiles[block.y * side + block.x, default: []].append(Candidate(map: map, block: block)) }
        }
        var winners: [(key: Int, winner: Candidate, others: [Candidate])] = []
        for key in tiles.keys.sorted() {
            let candidates = tiles[key] ?? []
            let best = candidates.min { left, right in
                if left.block.bytes != right.block.bytes { return left.block.bytes > right.block.bytes }
                let leftBase = left.map == inPlace, rightBase = right.map == inPlace
                if leftBase != rightBase { return leftBase }
                return left.map < right.map
            }
            guard let best else { continue }
            winners.append((key, best, candidates.filter { $0.map != best.map }))
        }

        // A block that is copied has to be there, with the size its manifest says.
        for entry in winners where entry.winner.map != inPlace {
            let source = inputs[entry.winner.map].appendingPathComponent(entry.winner.block.file)
            let size = (try? fileManager.attributesOfItem(atPath: source.path))?[.size] as? Int
            guard let size, Int64(size) == entry.winner.block.bytes else {
                throw MapBuilderError("The block \(entry.winner.block.x)/\(entry.winner.block.y) of \(inputs[entry.winner.map].lastPathComponent) is missing or damaged; build it again first.")
            }
        }

        // Write: new files first (the manifest that is there does not list them), the manifest last.
        let blocksFolder = output.appendingPathComponent("blocks", isDirectory: true)
        let outputExisted = fileManager.fileExists(atPath: output.path)
        var finished = false
        // A merge into a new folder that stops leaves nothing behind.
        defer {
            if !finished && inPlace == nil {
                try? fileManager.removeItem(at: blocksFolder)
                if !outputExisted { try? fileManager.removeItem(at: output) }
            }
        }
        do { try fileManager.createDirectory(at: blocksFolder, withIntermediateDirectories: true) } catch {
            throw MapBuilderError("Cannot create \(blocksFolder.path): \(error.localizedDescription)")
        }
        let toWrite = winners.filter { $0.winner.map != inPlace }
        var merged: [Int: StoreManifest.Block] = [:]
        if let base = inPlace { for block in manifests[base].blocks { merged[block.y * side + block.x] = block } }
        var written = 0
        var replaced = 0
        var temporaries: [URL] = []
        defer { for url in temporaries { try? fileManager.removeItem(at: url) } }
        var pending: [(temporary: URL, target: URL)] = []
        var superseded: [String] = []
        for entry in toWrite {
            try Task.checkCancellation()
            var block = entry.winner.block
            // A block that replaces another gets a name of its own: the manifest is what switches to it, so the old one is whole until then.
            let replacing = merged[entry.key]
            let suffix = replacing == nil ? "" : "-\(UUID().uuidString.prefix(8).lowercased())"
            let name = "blocks/\(first.blockZoom)-\(block.x)-\(block.y)\(suffix).gmk"
            let target = output.appendingPathComponent(name)
            let temporary = blocksFolder.appendingPathComponent(".merge-\(UUID().uuidString)")
            do { try fileManager.copyItem(at: inputs[entry.winner.map].appendingPathComponent(block.file), to: temporary) } catch {
                throw MapBuilderError("Cannot copy the block \(block.x)/\(block.y) of \(inputs[entry.winner.map].lastPathComponent): \(error.localizedDescription)")
            }
            temporaries.append(temporary)
            if let replacing { replaced += 1; superseded.append(replacing.file) }
            block.file = name
            merged[entry.key] = block
            pending.append((temporary, target))
            written += 1
            progress(written, toWrite.count)
        }
        for item in pending {
            // A file that is there and not listed is left from a merge that stopped.
            try? fileManager.removeItem(at: item.target)
            try fileManager.moveItem(at: item.temporary, to: item.target)
        }
        temporaries = []

        var manifest = inPlace.map { manifests[$0] } ?? first
        if inPlace == nil { manifest.levels = [] }
        manifest.blocks = merged.keys.sorted().compactMap { merged[$0] }
        var credits: [String] = []
        for text in manifests.map(\.attribution) where !credits.contains(text) { credits.append(text) }
        manifest.attribution = credits.joined(separator: " | ")
        try manifest.validate()
        let manifestURL = output.appendingPathComponent("manifest.json")
        if inPlace != nil {
            // The manifest from before is kept next to it, in case the merge has to be undone by hand.
            let backup = output.appendingPathComponent("manifest.before-merge.json")
            try? fileManager.removeItem(at: backup)
            try? fileManager.copyItem(at: manifestURL, to: backup)
        }
        try Self.write(manifest, to: manifestURL)
        finished = true
        // The blocks that were replaced are no longer listed: their files go.
        for file in superseded { try? fileManager.removeItem(at: output.appendingPathComponent(file)) }

        let overlaps = winners.filter { !$0.others.isEmpty }.map { entry in
            MapMergeReport.Overlap(
                x: entry.winner.block.x, y: entry.winner.block.y, kept: inputs[entry.winner.map].lastPathComponent,
                keptBytes: entry.winner.block.bytes, dropped: entry.others.map { inputs[$0.map].lastPathComponent },
                droppedBytes: entry.others.map(\.block.bytes))
        }
        var warnings: [String] = []
        if !overlaps.isEmpty {
            warnings.append("\(overlaps.count) tiles were in more than one map: the larger block was kept. A border tile can miss the other country's side until it is built again.")
        }
        let nextSteps = ["Run fill-sea on the merged map, then build-levels, to close the sea between the maps and build the levels of the tiles that changed."]
        return MapMergeReport(
            blocks: manifest.blocks.count, written: written, replaced: replaced, overlaps: overlaps, hasLevels: !manifest.levels.isEmpty,
            warnings: warnings, nextSteps: nextSteps)
    }

    /// What differs between two manifests that must agree to be merged, or `nil`.
    private static func difference(_ first: StoreManifest, _ other: StoreManifest) -> String? {
        if first.formatVersion != other.formatVersion { return "the block format is \(other.formatVersion), not \(first.formatVersion)" }
        if first.classifierVersion != other.classifierVersion { return "the rule table is \(other.classifierVersion), not \(first.classifierVersion): build one of them again" }
        if first.storageZoom != other.storageZoom { return "the storage zoom is \(other.storageZoom), not \(first.storageZoom)" }
        if first.blockZoom != other.blockZoom { return "the block zoom is \(other.blockZoom), not \(first.blockZoom)" }
        if first.bands != other.bands { return "the bands differ" }
        if first.profile != other.profile { return "the profile is \(other.profile), not \(first.profile)" }
        return nil
    }
}
