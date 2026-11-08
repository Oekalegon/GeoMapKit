/// Where the list of regions comes from.
///
/// A protocol so that the Geofabrik index can be replaced by a catalog of our own for hosted area files, and so that tests need
/// no network.
public protocol RegionCatalog: Sendable {
    /// The regions.
    ///
    /// - Throws: ``RegionError`` if the catalog is not valid, or the network or file error that kept it from being read.
    func index() async throws -> RegionIndex
}
