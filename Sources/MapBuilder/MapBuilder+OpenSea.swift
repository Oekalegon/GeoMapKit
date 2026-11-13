import FeatureStore
import FeatureStoreBuilder
import Foundation
import GeoCore
import OSMPBF
import Regions


extension MapBuilder {
    /// Fills the open sea of a set (`OpenSea`, questions 61 and 62): the blocks that no source outline touches, the empty or border-only
    /// blocks inside the outline of a big region, and the empty cells between the islands of a block with a coast.
    ///
    /// The blocks of the grid inside the bounding box of the set whose tile is touched by no region without regions below it in the Geofabrik index (a leaf) hold no land,
    /// so they are open sea; they are given their sea where they touch a block that shows sea. This is the hole in the middle of a sea
    /// between the blocks of the coasts around it, which `build-region` does not see because it only plans the blocks of its own area.
    /// The files are written, and the manifest after each; the levels of the blocks that change are out of date (`build-levels` finds
    /// them by comparing the blocks they came from).
    ///
    /// - Parameters:
    ///   - folder: The folder of the set of blocks.
    ///   - cacheDirectory: The cache folder with the region index, or `nil` for the default one.
    ///   - catalog: The list of regions, or `nil` for the Geofabrik index kept in the cache folder.
    ///   - downloader: The network for the region index, or `nil` for `URLSession`.
    ///   - userAgent: The user agent of that `URLSession`; an app passes its own name.
    /// - Returns: What was done.
    /// - Throws: ``MapBuilderError`` for a folder with no usable manifest, a profile that is not `full` and the errors of the files.
    public static func fillOpenSea(
        folder: URL, cacheDirectory: URL? = nil, catalog: (any RegionCatalog)? = nil, downloader: (any Downloader)? = nil,
        userAgent: String = MapBuilder.defaultUserAgent
    ) async throws -> OpenSea.Report {
        let manifestURL = folder.appendingPathComponent("manifest.json")
        let manifest: StoreManifest
        do {
            manifest = try StoreManifest(json: try Data(contentsOf: manifestURL))
        } catch {
            throw MapBuilderError("Cannot read \(manifestURL.path): \(error.localizedDescription)")
        }
        guard manifest.profile == "full" else { throw MapBuilderError("Only a set of the full profile has open sea to fill.") }
        guard let first = manifest.blocks.first else { throw MapBuilderError("The set has no blocks.") }
        let directory = try cacheDirectory ?? SourceCache.defaultDirectory()
        let index = try await (catalog ?? GeofabrikCatalog(
            directory: directory, downloader: downloader ?? URLSessionDownloader(userAgent: userAgent))).index()

        // A region that has regions below it (a continent, or a country cut into states) is the sum of those, and a continent outline takes
        // in the whole sea around it (Europe covers the North Sea entirely): only the regions with none below them say where there is
        // data. A top-level region with no children (Russia in the Geofabrik index has some, a small island state has none) counts.
        let parents = Set(index.regions.compactMap(\.parentID))
        let leaves = try RegionIndex(regions: index.regions.filter { !parents.contains($0.id) })
        var columns = first.x...first.x, rows = first.y...first.y
        for block in manifest.blocks {
            columns = min(columns.lowerBound, block.x)...max(columns.upperBound, block.x)
            rows = min(rows.lowerBound, block.y)...max(rows.upperBound, block.y)
        }
        // Every other position of the grid inside the set has no file or no coast: the neighbours of each group decide (question 62).
        var outside = Set<OpenSea.Position>()
        var covered: [OpenSea.Position: [StoreManifest.Source]] = [:]
        for y in rows {
            for x in columns {
                guard let tile = TileID(zoom: manifest.blockZoom, x: x, y: y) else { continue }
                let box = BoundingBox(
                    south: tile.southEast.latitude, west: tile.northWest.longitude, north: tile.northWest.latitude, east: tile.southEast.longitude)
                let position = OpenSea.Position(x: x, y: y)
                if leaves.regions(covering: box, samplesPerSide: 16).coveredShare == 0 { outside.insert(position) } else { covered[position] = [] }
            }
        }
        // The empty cells of a coast block first: along the border of a block they would read as land and stop the block rule. Then the
        // block rule; the new sea blocks are squares to spread from. Repeated until nothing changes (a few rounds at most).
        var current = manifest
        var report = OpenSea.Report()
        for _ in 0..<6 {
            let cells = try OpenSea.fillEmptyCells(manifest: current, folder: folder) { updated in try Self.write(updated, to: manifestURL) }
            let blocks = try OpenSea.fill(manifest: cells.manifest, folder: folder, covered: covered, outside: outside) { updated in
                try Self.write(updated, to: manifestURL)
            }
            current = blocks.manifest
            for (position, count) in cells.cellsFilled { report.cellsFilled[position, default: 0] += count }
            report.created += blocks.report.created
            report.extended += blocks.report.extended
            report.left = blocks.report.left
            report.conflicting = blocks.report.conflicting
            if cells.cellsFilled.isEmpty && !blocks.report.changed { break }
        }
        return report
    }
}
