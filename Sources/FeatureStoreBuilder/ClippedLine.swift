import FeatureStore

/// One piece of a line inside one cell.
struct ClippedLine: Equatable {
    /// The vertices, in the direction of the original line. Clip points on the cell border are included.
    var points: [PackedPoint]
    /// The original line continues before the first vertex (the piece starts at a border or the line left and re-entered).
    var continuesBefore: Bool
    /// The original line continues after the last vertex.
    var continuesAfter: Bool
    /// The distance along the line from its start to the first vertex of the piece, in centimetres.
    var offsetCentimetres: UInt32

    /// The piece flags for the file format.
    var flags: FeatureFlags {
        var flags: FeatureFlags = []
        if continuesBefore { flags.insert(.continuesBefore) }
        if continuesAfter { flags.insert(.continuesAfter) }
        return flags
    }
}
