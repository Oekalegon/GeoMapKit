import FeatureStore

/// One stored piece of a line, as input for ``LineJoiner``.
struct LinePiece: Equatable {
    var points: [PackedPoint]
    var continuesBefore: Bool
    var continuesAfter: Bool
    var offset: UInt32
}
