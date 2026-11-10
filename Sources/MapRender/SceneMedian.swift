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
    /// The line halfway between the two carriageways, in screen points. Two carriageways are separated by a divider, so the
    /// renderer draws this line along the whole strip, in the colour of the road's outline.
    public var divider: [ScreenPoint]
    /// The index of the style variant of the class this feature is drawn with (see `ClassStyle.variants`), or `nil` for the class's own look.
    public var variant: Int? = nil

    /// Creates a median strip.
    public init(featureClass: FeatureClass, structure: Structure, ring: [ScreenPoint], divider: [ScreenPoint] = []) {
        self.featureClass = featureClass
        self.structure = structure
        self.ring = ring
        self.divider = divider
    }
}
