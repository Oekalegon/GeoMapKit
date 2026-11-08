import FeatureStore
import MapStyle

/// The strip between the two carriageways of a divided road, to fill in the colour of the road.
///
/// Where two one-way ways of the same class run side by side in opposite directions and are close, they are one road with a
/// divider between its lanes. Drawn as two roads, the divider shows as a gap in the road, and the sum of the two looks narrower
/// than the undivided road it comes from. The renderer fills the strip so that the pair reads as one road.
public struct SceneMedian: Sendable, Equatable {
    /// The class of the two carriageways.
    public var featureClass: FeatureClass
    /// Whether the carriageways are on the ground or on a bridge.
    public var structure: Structure
    /// The closed ring of the strip, in screen points: along the centre line of one carriageway and back along the other.
    public var ring: [ScreenPoint]

    /// Creates a median strip.
    public init(featureClass: FeatureClass, structure: Structure, ring: [ScreenPoint]) {
        self.featureClass = featureClass
        self.structure = structure
        self.ring = ring
    }
}
