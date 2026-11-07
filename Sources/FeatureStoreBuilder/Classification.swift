import FeatureStore

/// The result of classifying one OSM object.
public struct Classification: Hashable, Sendable {
    /// The derived class.
    public let featureClass: FeatureClass
    /// The subclass byte, see ``SubclassBits``.
    public let subclass: UInt8
    /// Point, line or area.
    public let kind: FeatureKind
    /// The lowest band the feature is stored in. It is stored in that band and all bands above it.
    public let minimumBand: ZoomBand
    /// Whether the fixed Watch profile includes the feature.
    public let showsOnWatch: Bool
}
