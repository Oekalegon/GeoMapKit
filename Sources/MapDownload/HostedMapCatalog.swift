/// Finds a ready-made map for an area.
public protocol HostedMapCatalog: Sendable {
    /// - Parameter area: The area wanted.
    /// - Returns: The map that covers the whole area, or `nil` if the server has none (or there is no server).
    /// - Throws: A network or format error; a caller then goes on as if there were none.
    func map(covering area: MapArea) async throws -> HostedMap?
}
