import FeatureStore
import Foundation
import GeoCore

/// Derives a coarse level of a set of blocks from its overview band (question 50).
///
/// The overview band of the source cells holds the geometry of every feature cut at the borders of the cells of zoom 13.
/// A level joins those pieces again (lines by their end points, areas by chaining the real edges of the rings), simplifies
/// the result for the top zoom of the level, leaves out what is smaller than three pixels there, and cuts it into the
/// larger cells of the level. A joined line or ring is cut at the border of the block before it is simplified (with the
/// points on that border kept), so two neighbouring blocks of a level agree on the border. No OSM file is read.
///
/// A level block is built from the source cells of its area and a margin around it, so a line or area that crosses the
/// border of the block is whole when it is judged for its size.
public enum LevelBuilder {
    /// The cells of the margin read around the block, in source cells: wider than the longest minimum size of a level
    /// (about 12 cells at the top zoom 3).
    public static let defaultMargin = 32

    /// The most source cells one block may read, margin included. The work keeps every piece of the area in memory, so it is
    /// meant for the blocks of the design (zoom 8 or coarser blocks of the levels with a top zoom of 3 or more); a larger
    /// area is refused.
    public static let maximumRegionCells = 250_000

    /// Builds the file of one block of a level.
    ///
    /// - Parameters:
    ///   - source: The blocks to derive from, for example a `StoreSet`. Read only.
    ///   - spec: The level.
    ///   - tile: The block of the level: a tile whose zoom is at most the storage zoom of the level. The file holds the
    ///     cells of the level inside it.
    ///   - margin: The source cells read around the block, 0 or more.
    /// - Returns: The file and what went into it, or `nil` if the block has nothing to store.
    /// - Throws: ``LevelError`` for a block or source that does not fit, and the errors of reading the source.
    public static func build(
        from source: any CellSource, spec: LevelSpec, tile: TileID, margin: Int = defaultMargin
    ) throws -> LevelResult? {
        guard source.bands.contains(.overview) else { throw LevelError.noOverviewBand }
        guard margin >= 0 else { throw LevelError.invalidTile("the margin is negative") }
        guard tile.zoom <= spec.storageZoom, spec.storageZoom < source.storageZoom else {
            throw LevelError.invalidTile(
                "block zoom \(tile.zoom), level cells \(spec.storageZoom), source cells \(source.storageZoom)")
        }
        let sourceZoom = source.storageZoom
        let side = 1 << sourceZoom
        let shift = sourceZoom - tile.zoom
        let region = LevelRegion(
            columns: max(0, (tile.x << shift) - margin)...min(side - 1, ((tile.x + 1) << shift) - 1 + margin),
            rows: max(0, (tile.y << shift) - margin)...min(side - 1, ((tile.y + 1) << shift) - 1 + margin))
        guard region.columns.count * region.rows.count <= maximumRegionCells else {
            throw LevelError.regionTooLarge(cells: region.columns.count * region.rows.count)
        }
        let levelShift = spec.storageZoom - tile.zoom
        let block = LevelRegion(
            columns: (tile.x << levelShift)...(((tile.x + 1) << levelShift) - 1),
            rows: (tile.y << levelShift)...(((tile.y + 1) << levelShift) - 1))

        // The course of a river in its own area (`riverName`) is read whenever the level has river lines: where the area is left out of
        // the level the river is drawn as a line again (see `writeLines`).
        var readClasses = spec.classes
        if readClasses.contains(FeatureClass.waterLine.rawValue) { readClasses.insert(FeatureClass.riverName.rawValue) }
        var collected = LevelCollection()
        var report = LevelReport()
        var firstFile: FeatureStoreFile?
        for y in region.rows {
            for x in region.columns {
                guard let cell = TileID(zoom: sourceZoom, x: x, y: y), let file = try source.file(containing: cell) else { continue }
                firstFile = firstFile ?? file
                report.cellsRead += 1
                for feature in try file.features(in: cell, band: .overview, classes: readClasses) {
                    report.featuresRead += 1
                    collected.add(feature, in: cell, of: file)
                }
            }
        }
        guard let firstFile else { return nil }

        let corner = tile.northWest, far = tile.southEast
        var writer = FeatureStoreWriter(
            storageZoom: spec.storageZoom,
            boundingBox: BoundingBox(south: far.latitude, west: corner.longitude, north: corner.latitude, east: far.longitude),
            attribution: source.attribution, classifierVersion: UInt16(truncatingIfNeeded: firstFile.classifierVersion))
        var output = LevelOutput(writer: writer, spec: spec, tile: tile, block: block, report: report)
        try output.writePoints(collected)
        // The areas first: a water area that is left out takes its outline (a line) with it.
        try output.writeAreas(collected, region: region)
        try output.writeLines(collected)
        writer = output.writer
        report = output.report
        guard writer.cellCount > 0 else { return nil }
        report.cellsWritten = writer.cellCount
        return LevelResult(data: try writer.data(), report: report)
    }
}
