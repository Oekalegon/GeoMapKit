/// What the Watch copy of a map holds: the classes and bands that `RegionCutter` keeps, and nothing else.
///
/// The Watch shows the essential minimum, so the copy has only the classes that have a Watch rule in the classifier, only the mid and
/// detail bands (the Watch does not zoom out to the overview), only the `name` of a feature and no relation table. The classes are the
/// ones of `BuildProfile.watch` in `FeatureStoreBuilder`; a test there checks that the two lists are the same.
public struct WatchProfile: Sendable, Equatable {
    /// The classes that are kept.
    public var classes: Set<FeatureClass>
    /// The bands that are kept.
    public var bands: [ZoomBand]

    /// Creates a profile.
    public init(classes: Set<FeatureClass>, bands: [ZoomBand]) {
        self.classes = classes
        self.bands = bands
    }

    /// The fixed Watch profile (provisional, like the Watch copy of the builder).
    public static let standard = WatchProfile(
        classes: [
            .path, .track, .roadMajor, .roadMinor, .roadService, .railway, .powerLine, .aerialway, .piste,
            .waterLine, .waterArea, .forest, .landcover, .glacier, .bareGround, .sand, .wetland,
            .peak, .place, .poiAnchor,
        ],
        bands: [.mid, .detail])
}
