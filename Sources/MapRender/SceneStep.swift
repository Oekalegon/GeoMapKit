import MapStyle

/// The features to draw in one ``DrawStep``.
///
/// A renderer draws all features of a step before it starts the next one. That order is what lets the outlines of
/// crossing roads join: all casings come in earlier steps than the fills.
public struct SceneStep: Sendable, Equatable {
    /// What to draw: a class and which part of it.
    public var step: DrawStep
    /// The lines of the class (for a casing step, only these are used).
    public var lines: [SceneLine]
    /// The area pieces of the class.
    public var areas: [SceneArea]
    /// The points of the class.
    public var points: [ScenePoint]
    /// The strips between the two carriageways of a divided road, to fill in the colour of the road.
    public var medians: [SceneMedian]

    /// Creates a step.
    public init(
        step: DrawStep, lines: [SceneLine] = [], areas: [SceneArea] = [], points: [ScenePoint] = [], medians: [SceneMedian] = []
    ) {
        self.step = step
        self.lines = lines
        self.areas = areas
        self.points = points
        self.medians = medians
    }
}
