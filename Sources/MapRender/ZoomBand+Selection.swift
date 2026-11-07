import FeatureStore

extension ZoomBand {
    /// The band whose geometry is drawn at a zoom level, if the file holds every band.
    ///
    /// Boundaries are provisional, see the architecture document: overview below zoom 12, mid from 12 to
    /// below 15, detail from 15. Zoom above the stored detail is overzoom: the detail geometry is scaled.
    public static func band(forZoom zoom: Double) -> ZoomBand {
        if zoom >= 15 { return .detail }
        if zoom >= 12 { return .mid }
        return .overview
    }

    /// The band to read for a zoom level from the bands a file actually holds.
    ///
    /// The wanted band is used when present. Otherwise the nearest finer band is used (the Watch file has no
    /// overview band, so zoom 10 shows the mid band), and if there is none, the nearest coarser one.
    ///
    /// - Returns: The band, or `nil` if `available` is empty.
    public static func band(forZoom zoom: Double, available: [ZoomBand]) -> ZoomBand? {
        let wanted = band(forZoom: zoom)
        if available.contains(wanted) { return wanted }
        if let finer = available.filter({ $0 > wanted }).min() { return finer }
        return available.filter { $0 < wanted }.max()
    }
}
