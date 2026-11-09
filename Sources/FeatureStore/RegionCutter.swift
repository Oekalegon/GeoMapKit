import Foundation
import GeoCore

/// Cuts a small copy for the Watch out of a bigger map, on the phone.
///
/// The cutter reads the cells that touch an area from a ``CellSource`` (one store file or a set of blocks) and writes one store
/// file with the cells, as far as ``WatchProfile`` keeps them: the classes and bands of the profile, the name of each feature,
/// and no relation table. The Watch only reads the file.
///
/// Cells are copied whole and not cut again, so the copy is always whole cells: its edge is a cell edge, and the pieces of a line or
/// an area that continue into the next cell keep their flags and their offsets. The strings are read from the file that holds the
/// cell and written to one new table, so the copy does not depend on the blocks it came from.
///
/// A cut is synchronous and reads and writes files: call it off the main thread.
public struct RegionCutter: Sendable {
    /// Where the cells come from.
    public let source: any CellSource
    /// What is kept.
    public let profile: WatchProfile
    /// The most cells at the storage zoom an area may cover, 4,000 by default (about 25 km across at zoom 13 in the north of Norway).
    public let maximumCells: Int

    /// Creates a cutter.
    ///
    /// - Parameters:
    ///   - source: The map to cut from. Its cells at the storage zoom are used, not its coarse levels.
    ///   - profile: What to keep, the fixed Watch profile by default.
    ///   - maximumCells: The largest area, in cells, that ``cut(area:to:)`` accepts; at least 1.
    public init(source: any CellSource, profile: WatchProfile = .standard, maximumCells: Int = 4_000) {
        self.source = source
        self.profile = profile
        self.maximumCells = max(maximumCells, 1)
    }

    /// The cells that touch an area.
    ///
    /// - Parameter area: The area in degrees.
    /// - Returns: The cell range, columns and rows at the storage zoom.
    /// - Throws: ``RegionCutError/invalidArea`` or ``RegionCutError/tooLarge(cells:limit:)``.
    public func cells(of area: BoundingBox) throws -> (columns: ClosedRange<Int>, rows: ClosedRange<Int>) {
        guard area.south.isFinite, area.west.isFinite, area.north.isFinite, area.east.isFinite,
            area.south <= area.north, area.west <= area.east, area.west >= -180, area.east < 180,
            let northWest = TileID.containing(Coordinate(latitude: area.north, longitude: area.west), zoom: source.storageZoom),
            let southEast = TileID.containing(Coordinate(latitude: area.south, longitude: area.east), zoom: source.storageZoom)
        else { throw RegionCutError.invalidArea }
        let columns = northWest.x...southEast.x
        let rows = northWest.y...southEast.y
        let count = columns.count * rows.count
        guard count <= maximumCells else { throw RegionCutError.tooLarge(cells: count, limit: maximumCells) }
        return (columns, rows)
    }

    /// Cuts the area out of the source and writes the copy, replacing a file that is there.
    ///
    /// - Parameters:
    ///   - area: The area in degrees; the copy holds every cell that touches it.
    ///   - url: Where to write the file.
    /// - Returns: What the cut came to.
    /// - Throws: ``RegionCutError`` for an area that is not valid, too large or empty, or for a file that cannot be read or written.
    @discardableResult
    public func cut(area: BoundingBox, to url: URL) throws -> CutReport {
        let range = try cells(of: area)
        let zoom = source.storageZoom
        // The box of the copy is the box of the cells, so that a reader sees where the map ends.
        guard let first = TileID(zoom: zoom, x: range.columns.lowerBound, y: range.rows.lowerBound),
            let last = TileID(zoom: zoom, x: range.columns.upperBound, y: range.rows.upperBound)
        else { throw RegionCutError.invalidArea }
        let box = BoundingBox(
            south: last.southEast.latitude, west: first.northWest.longitude, north: first.northWest.latitude, east: last.southEast.longitude)
        let classIDs = Set(profile.classes.map(\.rawValue))
        var report = CutReport(cellsExamined: 0, cellsWritten: 0, featuresWritten: 0, fileBytes: 0)
        // The writer is made at the first file that holds a cell, for the version of the class table of that file.
        var writer: FeatureStoreWriter?
        do {
            for y in range.rows {
                for x in range.columns {
                    guard let cell = TileID(zoom: zoom, x: x, y: y) else { continue }
                    report.cellsExamined += 1
                    guard let file = try source.file(containing: cell) else { continue }
                    var target = writer ?? FeatureStoreWriter(
                        storageZoom: zoom, boundingBox: box, attribution: source.attribution,
                        classifierVersion: UInt16(truncatingIfNeeded: file.classifierVersion))
                    writer = nil
                    defer { writer = target }
                    var written = false
                    for band in profile.bands {
                        for var feature in try file.features(in: cell, band: band, classes: classIDs) {
                            // Strings are numbers of the string table of the file they were read from: write them to the new table.
                            feature.nameID = feature.nameID.flatMap { file.stringBytes(at: $0) }.map { target.intern([UInt8]($0)) }
                            feature.tags = []
                            try target.add(feature, band: band, cell: cell)
                            report.featuresWritten += 1
                            written = true
                        }
                    }
                    if written { report.cellsWritten += 1 }
                }
            }
            guard let writer, report.featuresWritten > 0 else { throw RegionCutError.emptyArea }
            let data = try writer.data()
            try data.write(to: url, options: .atomic)
            report.fileBytes = data.count
        } catch let error as FeatureStoreError {
            throw RegionCutError.store(error)
        }
        return report
    }
}
