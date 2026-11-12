import FeatureStore
import FeatureStoreBuilder
import Foundation
import GeoCore
import OSMPBF
import Regions
import ToolSupport

extension ToolRunner {
    /// Fills the blocks of a set that no source outline touches with sea (``OpenSea``, question 61).
    ///
    /// The blocks of the grid inside the bounding box of the set whose tile is touched by no region below a continent in the Geofabrik index hold no land,
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
    /// - Returns: What was done.
    /// - Throws: ``ToolError`` for a folder with no usable manifest, a profile that is not `full` and the errors of the files.
    public static func fillOpenSea(
        folder: URL, cacheDirectory: URL? = nil, catalog: (any RegionCatalog)? = nil, downloader: (any Downloader)? = nil
    ) async throws -> OpenSea.Report {
        let manifestURL = folder.appendingPathComponent("manifest.json")
        let manifest: StoreManifest
        do {
            manifest = try StoreManifest(json: try Data(contentsOf: manifestURL))
        } catch {
            throw ToolError("Cannot read \(manifestURL.path): \(error.localizedDescription)")
        }
        guard manifest.profile == "full" else { throw ToolError("Only a set of the full profile has open sea to fill.") }
        guard let first = manifest.blocks.first else { throw ToolError("The set has no blocks.") }
        let directory = try cacheDirectory ?? SourceCache.defaultDirectory()
        let index = try await (catalog ?? GeofabrikCatalog(
            directory: directory, downloader: downloader ?? URLSessionDownloader(userAgent: userAgent))).index()

        // The regions of a continent have no parent and their outlines take in the whole sea around them (Europe covers the North Sea
        // entirely): only the regions below them say where there is data.
        let leaves = try RegionIndex(regions: index.regions.filter { $0.parentID != nil })
        var columns = first.x...first.x, rows = first.y...first.y
        for block in manifest.blocks {
            columns = min(columns.lowerBound, block.x)...max(columns.upperBound, block.x)
            rows = min(rows.lowerBound, block.y)...max(rows.upperBound, block.y)
        }
        var outside = Set<OpenSea.Position>()
        for y in rows {
            for x in columns {
                guard let tile = TileID(zoom: manifest.blockZoom, x: x, y: y) else { continue }
                let box = BoundingBox(
                    south: tile.southEast.latitude, west: tile.northWest.longitude, north: tile.northWest.latitude, east: tile.southEast.longitude)
                if leaves.regions(covering: box, samplesPerSide: 16).coveredShare == 0 { outside.insert(OpenSea.Position(x: x, y: y)) }
            }
        }
        let (_, report) = try OpenSea.fill(manifest: manifest, folder: folder, covered: [:], outside: outside) { updated in
            try Self.write(updated, to: manifestURL)
        }
        return report
    }
}
