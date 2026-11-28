import Foundation

/// The catalog on a server: reads its index file and picks from it.
public struct URLSessionHostedMapCatalog: HostedMapCatalog {
    private let indexURL: URL?

    /// - Parameter indexURL: The address of the server's `index.json`, or `nil` when there is no server: nothing is asked then.
    public init(indexURL: URL?) { self.indexURL = indexURL }

    public func map(covering area: MapArea) async throws -> HostedMap? {
        guard let indexURL else { return nil }
        let (data, response) = try await URLSession.shared.data(from: indexURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try HostedMapIndex.decode(data).map(covering: area)
    }
}
