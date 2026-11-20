/// Why a heat map frame has nothing in it, as far as that can be told from what is known.
public enum HeatMapEmptiness: Sendable, Equatable {
    /// The database has no counted pieces at all: nothing was stored along ways (the tracks did not follow lines of the map, they are of
    /// a category that is not matched, or an import did not finish).
    case databaseHasNoCounts
    /// The map has no lines in the area (outside the map, or a place with no paths).
    case noWaysInArea
    /// The frame was made for some categories or months, and nothing was counted in them; there are counts in the database.
    case nothingInFilter
    /// The area has lines and the frame has no filter, but the counts are on other ways: they are somewhere else.
    case countsElsewhere
}

extension HeatMapFrame {
    /// Why the frame is empty, or `nil` when it has buckets.
    ///
    /// - Parameter databaseCountedPieces: The pieces of 10 m that have a count in the whole database (``TrackStore/countedBucketCount()``).
    public func emptiness(databaseCountedPieces: Int) -> HeatMapEmptiness? {
        guard bucketCount == 0 else { return nil }
        if databaseCountedPieces <= 0 { return .databaseHasNoCounts }
        if waysInArea == 0 { return .noWaysInArea }
        return isFiltered ? .nothingInFilter : .countsElsewhere
    }
}
