/// A line width that follows the real road width on the ground.
///
/// Roads are drawn as wide as they are once the map is zoomed in far enough. The
/// width comes from the `lanes` tag: `lanes × metresPerLane`. Without a usable tag,
/// ``defaultLanes`` applies. The tag counts the lanes of the whole carriageway, both
/// directions together, so it is used as it is.
public struct GroundWidth: Sendable, Equatable {
    /// The width of one lane in metres.
    public var metresPerLane: Double
    /// The number of lanes assumed when the feature has no valid `lanes` tag.
    public var defaultLanes: Double
    /// The largest number of lanes taken from a tag, to ignore typing errors in the data.
    public var maximumLanes: Double

    /// Creates a ground width.
    public init(metresPerLane: Double, defaultLanes: Double, maximumLanes: Double = 12) {
        self.metresPerLane = metresPerLane
        self.defaultLanes = defaultLanes
        self.maximumLanes = maximumLanes
    }

    /// The width in metres for a feature with the given `lanes` value.
    ///
    /// A `nil` value, or one below 1, gives ``defaultLanes``.
    public func metres(lanes: Int?) -> Double {
        let count = lanes.flatMap { $0 >= 1 ? min(Double($0), maximumLanes) : nil } ?? defaultLanes
        return count * metresPerLane
    }
}
