import FeatureStore

/// The sea of the stored area, made from the coastlines and ready to be stored.
struct PreparedSea {
    let joined: CoastlineJoiner.Result
    let whole: SeaBuilder.Result
    let block: CellRect
    /// Whether the whole block is sea although no coastline is in it: assumed, see `FeatureStoreBuilder.build(from:writing:assumeSea:)`.
    var isOpenSea = false
}
