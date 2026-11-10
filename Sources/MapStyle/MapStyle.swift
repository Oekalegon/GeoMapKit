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
    /// The amount added to the layers of a class for its bridges, so they are drawn after all lines on the ground. Class layers
    /// stay below it.
    public static let bridgeLayerOffset = 100
    /// The layer of tunnels: above the area fills (layers up to 14) and below the lines on the ground (20 and up).
    public static let tunnelLayer = 15

    /// A name for diagnostics.
    public var name: String
    /// The colour behind everything.
    public var background: MapColor
    /// The styles by class. A class that is not in the dictionary is not drawn.
    public var classes: [FeatureClass: ClassStyle]
    /// How the data credit is shown on the map. See ``AttributionDisplay`` for the app's duty when this is hidden.
    public var attribution: AttributionDisplay
    /// How many labels are shown and how closely they may sit together. See ``LabelSettings``.
    public var labels: LabelSettings

    /// Creates a style.
    public init(
        name: String, background: MapColor, classes: [FeatureClass: ClassStyle], attribution: AttributionDisplay = .full,
        labels: LabelSettings = LabelSettings()
    ) {
        self.name = name
        self.background = background
        self.classes = classes
        self.attribution = attribution
        self.labels = labels
    }

    /// The style of a class, or `nil` if the class is hidden in this style.
    public func style(for featureClass: FeatureClass) -> ClassStyle? {
        classes[featureClass]
    }

    /// The style of a class for the features of one variant (`nil` for the features in no variant): the class's style with what the
    /// variant sets. `nil` if the class is hidden in this style or the index is not a variant of it.
    public func style(for featureClass: FeatureClass, variant: Int?) -> ClassStyle? {
        guard let style = classes[featureClass] else { return nil }
        guard let variant else { return style }
        guard style.variants.indices.contains(variant) else { return nil }
        return style.applying(style.variants[variant])
    }

    /// The style of what a draw step draws.
    public func style(for step: DrawStep) -> ClassStyle? {
        style(for: step.featureClass, variant: step.variant)
    }

    /// The classes drawn at a zoom level, in drawing order (lowest layer first).
    ///
    /// Classes on the same layer are ordered by their raw value, so the order is deterministic.
    public func visibleClasses(atZoom zoom: Double) -> [FeatureClass] {
        classes
            .filter { entry in
                entry.value.visibleZoom.contains(zoom) || entry.value.variants.contains { ($0.visibleZoom ?? entry.value.visibleZoom).contains(zoom) }
            }
            .sorted { ($0.value.layer, $0.key.rawValue) < ($1.value.layer, $1.key.rawValue) }
            .map(\.key)
    }

    /// The raw class IDs for `FeatureStoreFile.features(in:band:classes:)` at a zoom level.
    public func visibleClassIDs(atZoom zoom: Double) -> Set<UInt8> {
        Set(visibleClasses(atZoom: zoom).map(\.rawValue))
    }

    /// The steps to draw at a zoom level, in drawing order.
    ///
    /// A class with a stroke casing gets a ``DrawStep/Part/casing`` step on its ``ClassStyle/casingLayer``
    /// (or on its own layer when that is `nil`) and a ``DrawStep/Part/body`` step on its layer. Casing steps
    /// come before body steps of the same layer. A renderer draws every feature of a step before the next
    /// step, which is what makes outlines of crossing roads join.
    ///
    /// A class with a ``ClassStyle/bridge`` gets further steps for its bridges, on its layers plus
    /// ``bridgeLayerOffset``: a casing step and a body step, so bridges come after every line on the ground. A class with a
    /// ``ClassStyle/tunnel`` gets a body step for its tunnels on layer ``tunnelLayer``, above the area fills and below the
    /// lines on the ground. The steps on the ground then draw only the lines that are on the ground.
    public func drawSteps(atZoom zoom: Double) -> [DrawStep] {
        var steps: [(layer: Int, phase: Int, raw: UInt8, variant: Int, step: DrawStep)] = []
        for featureClass in visibleClasses(atZoom: zoom) {
            guard let classStyle = classes[featureClass] else { continue }
            // The features of the class that are in no variant, then each variant on its own look.
            let looks: [(variant: Int?, style: ClassStyle)] =
                [(nil, classStyle)] + classStyle.variants.indices.map { ($0, classStyle.applying(classStyle.variants[$0])) }
            for (variant, style) in looks where style.visibleZoom.contains(zoom) && !(variant.map { classStyle.variants[$0].hidden } ?? false) {
                let order = variant ?? -1
                func add(_ layer: Int, _ phase: Int, _ part: DrawStep.Part, _ structure: Structure) {
                    steps.append((layer, phase, featureClass.rawValue, order, DrawStep(featureClass: featureClass, part: part, structure: structure, variant: variant)))
                }
                if style.stroke?.casing != nil { add(style.casingLayer ?? style.layer, 0, .casing, .ground) }
                add(style.layer, 1, .body, .ground)
                guard style.stroke != nil else { continue }
                if style.bridge != nil {
                    add(Self.bridgeLayerOffset + (style.casingLayer ?? style.layer), 0, .casing, .bridge)
                    add(Self.bridgeLayerOffset + style.layer, 1, .body, .bridge)
                }
                if style.tunnel != nil { add(Self.tunnelLayer, 1, .body, .tunnel) }
            }
        }
        steps.sort { ($0.layer, $0.phase, $0.raw, $0.variant) < ($1.layer, $1.phase, $1.raw, $1.variant) }
        return steps.map(\.step)
    }
}
