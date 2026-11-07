import FeatureStore

/// A complete map style: a background and a ``ClassStyle`` per ``FeatureClass``.
///
/// Styles work on derived classes only, never on raw OSM tags, so a rule-table
/// change in the builder does not touch them. A class without an entry is hidden;
/// that is how the Watch style leaves out classes. The only tag a renderer reads
/// for drawing is `lanes`, which feeds ``LineWidth/resolved(atZoom:metresPerPoint:lanes:)``.
///
/// ``standard`` is the style for iOS, iPadOS and macOS; ``watch`` is the reduced,
/// high-contrast style for the Watch.
public struct MapStyle: Sendable, Equatable {
    /// A name for diagnostics.
    public var name: String
    /// The colour behind everything.
    public var background: MapColor
    /// The styles by class. A class that is not in the dictionary is not drawn.
    public var classes: [FeatureClass: ClassStyle]

    /// Creates a style.
    public init(name: String, background: MapColor, classes: [FeatureClass: ClassStyle]) {
        self.name = name
        self.background = background
        self.classes = classes
    }

    /// The style of a class, or `nil` if the class is hidden in this style.
    public func style(for featureClass: FeatureClass) -> ClassStyle? {
        classes[featureClass]
    }

    /// The classes drawn at a zoom level, in drawing order (lowest layer first).
    ///
    /// Classes on the same layer are ordered by their raw value, so the order is deterministic.
    public func visibleClasses(atZoom zoom: Double) -> [FeatureClass] {
        classes
            .filter { $0.value.visibleZoom.contains(zoom) }
            .sorted { ($0.value.layer, $0.key.rawValue) < ($1.value.layer, $1.key.rawValue) }
            .map(\.key)
    }

    /// The raw class IDs for `FeatureStoreFile.features(in:band:classes:)` at a zoom level.
    public func visibleClassIDs(atZoom zoom: Double) -> Set<UInt8> {
        Set(visibleClasses(atZoom: zoom).map(\.rawValue))
    }
}
