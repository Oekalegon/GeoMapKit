/// Why a heat map frame has nothing in it, as far as that can be told from what is known.
public enum HeatMapEmptiness: Sendable, Equatable {
    /// The database has no counted pieces and no off-track lines at all: nothing was stored (the tracks have no times, or an import did
    /// not finish).
    case databaseHasNoCounts
    /// The map has no lines in the area (outside the map, or a place with no paths).
    case noWaysInArea
    /// The frame was made for some categories or months, and nothing was counted in them; there are counts in the database.
    case nothingInFilter
    /// The area has lines and the frame has no filter, but the counts and traces are elsewhere.
    case countsElsewhere
}

extension HeatMapFrame {
    /// Why the frame is empty, or `nil` when it has buckets or traces.
    ///
    /// - Parameters:
    ///   - databaseCountedPieces: The pieces of 10 m that have a count in the whole database (`TrackStore.countedBucketCount()`).
    ///   - databaseOffTrackLines: The off-track lines in the whole database (`TrackStore.offTrackLineCount()`); they become the traces.
    public func emptiness(databaseCountedPieces: Int, databaseOffTrackLines: Int = 0) -> HeatMapEmptiness? {
        guard bucketCount == 0, traceCount == 0 else { return nil }
        if databaseCountedPieces <= 0, databaseOffTrackLines <= 0 { return .databaseHasNoCounts }
        // Without paths in the area a frame can still have traces, so it was empty of those too.
        if waysInArea == 0 { return .noWaysInArea }
        return isFiltered ? .nothingInFilter : .countsElsewhere
    }
}
