import FeatureStore
import MapStyle

/// The strip between the two carriageways of a divided road, to fill in the colour of the road.
///
/// Where two one-way ways of the same class run side by side in opposite directions and are close, they are one road with a
/// divider between its lanes. Drawn as two roads, the divider shows as a gap in the road, and the sum of the two looks narrower
/// than the undivided road it comes from. The renderer fills the strip so that the pair reads as one road. A style whose road colour
/// is translucent gets no strip (it would be blended twice where it overlaps the carriageways), and a street that crosses the gap is
/// drawn under the strip when the street is of a lower layer.
public struct SceneMedian: Sendable, Equatable {
    /// The class of the two carriageways.
    public var featureClass: FeatureClass
    /// Whether the carriageways are on the ground or on a bridge.
    public var structure: Structure
    /// The closed ring of the strip, in screen points: along the centre line of one carriageway and back along the other.
    public var ring: [ScreenPoint]
    /// The lines halfway between the two carriageways, in screen points: the stretches where they are far enough apart to have
    /// a divider between them. The renderer draws them in the colour of the road's outline, so the two lanes can still be told
    /// apart; where the carriageways come together there is none, so a divider does not end in the middle of a solid road.
    public var dividers: [[ScreenPoint]]

    /// Creates a median strip.
    public init(featureClass: FeatureClass, structure: Structure, ring: [ScreenPoint], dividers: [[ScreenPoint]] = []) {
        self.featureClass = featureClass
        self.structure = structure
        self.ring = ring
        self.dividers = dividers
    }
}
