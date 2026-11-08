import FeatureStore

/// One sample on a line: where it is, in degrees (as stored) and in metres, and which way the line runs.
struct LineSample {
    var point: PackedPoint
    var x: Double
    var y: Double
    /// The unit direction of the segment the sample lies on, in metres.
    var directionX: Double
    var directionY: Double
}
