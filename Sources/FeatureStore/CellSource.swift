import GeoCore

/// Where a map gets its cells from: one store file, or a set of block files.
///
/// A cell lives in exactly one file, and the strings of a feature (its name and tags) are numbers in the string table of that
/// file. So a reader asks for the file that holds a cell and reads the cell and its strings from that file.
public protocol CellSource: Sendable {
    /// The zoom of the cells.
    var storageZoom: Int { get }
    /// The bands the source holds.
    var bands: [ZoomBand] { get }
    /// The data credit that goes with the map.
    var attribution: String { get }

    /// The file that holds a cell.
    ///
    /// - Parameter cell: A cell at the storage zoom.
    /// - Returns: The file, or `nil` if no file holds the cell (outside the stored area, or a cell that is empty).
    /// - Throws: A ``FeatureStoreError`` or ``StoreSetError`` if the file cannot be read.
    func file(containing cell: TileID) throws -> FeatureStoreFile?
}

extension FeatureStoreFile: CellSource {
    public func file(containing cell: TileID) throws -> FeatureStoreFile? {
        try containsCell(cell) ? self : nil
    }
}
