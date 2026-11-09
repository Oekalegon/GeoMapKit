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
    /// The most cells at the storage zoom an area may cover, 1,000 by default. A cell is about 4.9 km wide at the equator and about 1.7 km at
    /// 70° north, so 1,000 cells (32 × 32) are about 55 km across there. The number is a guess until the room on the Watch is known.
    public let maximumCells: Int

    /// Creates a cutter.
    ///
    /// - Parameters:
    ///   - source: The map to cut from. Its cells at the storage zoom are used, not its coarse levels.
    ///   - profile: What to keep, the fixed Watch profile by default.
    ///   - maximumCells: The largest area, in cells, that ``cut(area:to:)`` accepts; at least 1.
    public init(source: any CellSource, profile: WatchProfile = .standard, maximumCells: Int = 1_000) {
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
    ///   - sourceDate: The date of the data, if known, for the header of the copy (a source does not tell it).
    /// - Returns: What the cut came to.
    /// - Throws: ``RegionCutError``: ``RegionCutError/invalidArea``, ``RegionCutError/tooLarge(cells:limit:)`` or
    ///   ``RegionCutError/emptyArea`` for the area, ``RegionCutError/store(_:)`` for a source that is not well formed, and
    ///   ``RegionCutError/io(_:)`` for a file that cannot be read or written.
    @discardableResult
    public func cut(area: BoundingBox, to url: URL, sourceDate: Date? = nil) throws -> CutReport {
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
        var writer: FeatureStoreWriter?
        var classifierVersion: UInt16?
        do {
            for y in range.rows {
                for x in range.columns {
                    guard let cell = TileID(zoom: zoom, x: x, y: y) else { continue }
                    report.cellsExamined += 1
                    guard let file = try source.file(containing: cell) else { continue }
                    // The class numbers of the copy are those of its source: files with another table cannot be mixed.
                    let version = UInt16(truncatingIfNeeded: file.classifierVersion)
                    if let classifierVersion, classifierVersion != version {
                        throw FeatureStoreError.corrupt("the files of the source have different class tables (\(classifierVersion) and \(version))")
                    }
                    classifierVersion = version
                    if writer == nil {
                        writer = FeatureStoreWriter(
                            storageZoom: zoom, boundingBox: box, attribution: source.attribution, sourceDate: sourceDate,
                            classifierVersion: version)
                    }
                    var written = false
                    for band in profile.bands {
                        for var feature in try file.features(in: cell, band: band, classes: classIDs) {
                            // Strings are numbers of the string table of the file they were read from: write them to the new table.
                            feature.nameID = try feature.nameID.map { id in
                                guard let bytes = file.stringBytes(at: id) else { throw FeatureStoreError.corrupt("name outside the string table") }
                                return writer!.intern([UInt8](bytes))
                            }
                            feature.tags = []
                            try writer!.add(feature, band: band, cell: cell)
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
        } catch let error as RegionCutError {
            throw error
        } catch let error as FeatureStoreError {
            throw RegionCutError.store(error)
        } catch {
            throw RegionCutError.io("\(error)")
        }
        return report
    }
}
