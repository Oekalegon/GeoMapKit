import FeatureStore

/// A different look for some of the features of a class: motorways among the major roads, farmland among the land cover, the tracks
/// with a gauge of 1,000 mm among the railways.
///
/// A variant selects by the subclass of the feature (``subclasses``, the names of ``SubclassNames``) and by tags (``tags``). A feature is in
/// a variant when it meets **all** of them; a variant with neither takes every feature of the class. The variants of a class are tried in
/// the order of the style file and the **first** that matches wins. A property that the variant sets replaces the class's own (the whole
/// ``fill``, ``stroke`` and so on, not a part of it); a property it leaves `nil` is the class's.
public struct StyleVariant: Sendable, Equatable {
    /// A name for the list in an editor.
    public var name: String
    /// The subclass names that match (`motorway`, `trunk`); empty for any subclass.
    public var subclasses: [String]
    /// The tag conditions, all of which must be met.
    public var tags: [TagCondition]
    /// The area fill instead of the class's, if set.
    public var fill: FillStyle?
    /// The line or outline instead of the class's, if set.
    public var stroke: StrokeStyle?
    /// The point symbol instead of the class's, if set.
    public var point: PointStyle?
    /// The label instead of the class's, if set.
    public var label: LabelStyle?
    /// The zoom range instead of the class's, if set.
    public var visibleZoom: ClosedRange<Double>?
    /// The drawing order instead of the class's (0 through 99), if set.
    public var layer: Int?
    /// The layer of the casing instead of the class's, if set.
    public var casingLayer: Int?
    /// How bridges are drawn instead of the class's, if set.
    public var bridge: BridgeStyle?
    /// How tunnels are drawn instead of the class's, if set.
    public var tunnel: TunnelStyle?

    /// Creates a variant.
    public init(
        name: String, subclasses: [String] = [], tags: [TagCondition] = [], fill: FillStyle? = nil, stroke: StrokeStyle? = nil,
        point: PointStyle? = nil, label: LabelStyle? = nil, visibleZoom: ClosedRange<Double>? = nil, layer: Int? = nil,
        casingLayer: Int? = nil, bridge: BridgeStyle? = nil, tunnel: TunnelStyle? = nil
    ) {
        self.name = name
        self.subclasses = subclasses
        self.tags = tags
        self.fill = fill
        self.stroke = stroke
        self.point = point
        self.label = label
        self.visibleZoom = visibleZoom
        self.layer = layer
        self.casingLayer = casingLayer
        self.bridge = bridge
        self.tunnel = tunnel
    }

    /// Whether a feature of a class is in this variant.
    ///
    /// - Parameters:
    ///   - subclass: The subclass byte of the feature (the bridge and tunnel bits are ignored).
    ///   - featureClass: The class of the feature, which gives the subclass its name.
    ///   - tag: The value of a tag of the feature, or `nil` if it has none (or the band does not hold it).
    public func matches(subclass: UInt8, in featureClass: FeatureClass, tag: (String) -> String?) -> Bool {
        if !subclasses.isEmpty {
            let value = SubclassBits.value(of: subclass)
            guard subclasses.contains(where: { SubclassNames.numbers(of: $0, in: featureClass).contains(value) }) else { return false }
        }
        return tags.allSatisfy { $0.isMet(by: tag($0.key)) }
    }

    /// Whether this variant selects nothing (it would take every feature of the class).
    public var selectsEverything: Bool { subclasses.isEmpty && tags.isEmpty }
}
