import FeatureStore

/// One step of drawing a class: its casing, or the class itself.
///
/// ``MapStyle/drawSteps(atZoom:)`` returns the steps in the order to draw them.
public struct DrawStep: Sendable, Equatable {
    /// What a step draws.
    public enum Part: Sendable, Equatable {
        /// Only the casing (outline) of the class's stroke, for every feature of the class.
        case casing
        /// Fill, stroke, point symbol and label. The casing is not repeated here.
        case body
    }

    /// The class to draw.
    public var featureClass: FeatureClass
    /// The part of the class to draw.
    public var part: Part

    /// Creates a step.
    public init(featureClass: FeatureClass, part: Part) {
        self.featureClass = featureClass
        self.part = part
    }
}
