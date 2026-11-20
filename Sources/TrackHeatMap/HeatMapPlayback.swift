/// What a ``HeatMapPlayer`` reports: the frame that is ready, the month it is for, and whether the player is stepping.
public struct HeatMapPlayback: Sendable {
    /// The number of the month of the frame, from 0 for the first.
    public let index: Int
    /// The frame.
    public let frame: HeatMapFrame
    /// Whether the player is stepping forward by itself.
    public let isPlaying: Bool
}
