import FeatureStore

/// The sea of the stored area, made from the coastlines and ready to be stored.
struct PreparedSea {
    let joined: CoastlineJoiner.Result
    let whole: SeaBuilder.Result
    let block: CellRect
}
