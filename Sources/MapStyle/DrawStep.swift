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
    /// Which lines of the class the step draws: those on the ground, the bridges or the tunnels. Areas and points are
    /// only drawn in steps on the ground.
    public var structure: Structure
    /// The index of the ``ClassStyle/variants`` entry this step draws, or `nil` for the features of the class that are in no variant.
    public var variant: Int?

    /// Creates a step.
    public init(featureClass: FeatureClass, part: Part, structure: Structure = .ground, variant: Int? = nil) {
        self.featureClass = featureClass
        self.part = part
        self.structure = structure
        self.variant = variant
    }
}
