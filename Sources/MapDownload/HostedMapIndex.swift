import Foundation

/// The list of ready-made maps a server holds: one JSON file, `index.json`, next to the map files.
///
/// ```json
/// { "formatVersion": 1, "maps": [
///   { "id": "utrecht-province", "name": "Utrecht", "url": "https://maps.example.org/utrecht-province.gmk", "bytes": 48000000,
///     "bounds": { "south": 51.9, "west": 4.7, "north": 52.3, "east": 5.6 }, "builtAt": "2026-11-28T00:00:00Z" } ] }
/// ```
///
/// `bytes` is the size of the file, `bounds` the area it covers (degrees) and `builtAt` an ISO 8601 date (optional). A file with another
/// `formatVersion` is refused, so a later layout can't be read as this one.
public struct HostedMapIndex: Codable, Equatable, Sendable {
    /// The layout of the index this code reads.
    public static let supportedFormatVersion = 1
    public var formatVersion: Int = HostedMapIndex.supportedFormatVersion
    public var maps: [HostedMap]

    public init(maps: [HostedMap]) { self.maps = maps }

    /// The smallest map that holds the whole area.
    ///
    /// - Parameter area: The area wanted.
    /// - Returns: The map, or `nil` when none covers the area.
    public func map(covering area: MapArea) -> HostedMap? {
        maps.filter { area.isCovered(by: $0.bounds) }.min { $0.bytes < $1.bytes }
    }

    /// Reads an index.
    ///
    /// - Throws: A `DecodingError` for JSON that is not an index, or one with another ``formatVersion``.
    public static func decode(_ data: Data) throws -> HostedMapIndex {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let index = try decoder.decode(HostedMapIndex.self, from: data)
        guard index.formatVersion == supportedFormatVersion else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "format version \(index.formatVersion)"))
        }
        return index
    }
}
