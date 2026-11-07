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
        var steps: [(layer: Int, phase: Int, raw: UInt8, step: DrawStep)] = []
        for featureClass in visibleClasses(atZoom: zoom) {
            guard let style = classes[featureClass] else { continue }
            if style.stroke?.casing != nil {
                let layer = style.casingLayer ?? style.layer
                steps.append((layer, 0, featureClass.rawValue, DrawStep(featureClass: featureClass, part: .casing)))
            }
            steps.append((style.layer, 1, featureClass.rawValue, DrawStep(featureClass: featureClass, part: .body)))
            guard style.stroke != nil else { continue }
            if style.bridge != nil {
                let casingLayer = Self.bridgeLayerOffset + (style.casingLayer ?? style.layer)
                steps.append((casingLayer, 0, featureClass.rawValue, DrawStep(featureClass: featureClass, part: .casing, structure: .bridge)))
                steps.append((
                    Self.bridgeLayerOffset + style.layer, 1, featureClass.rawValue,
                    DrawStep(featureClass: featureClass, part: .body, structure: .bridge)))
            }
            if style.tunnel != nil {
                steps.append((Self.tunnelLayer, 1, featureClass.rawValue, DrawStep(featureClass: featureClass, part: .body, structure: .tunnel)))
            }
        }
        steps.sort { ($0.layer, $0.phase, $0.raw) < ($1.layer, $1.phase, $1.raw) }
        return steps.map(\.step)
    }
}
