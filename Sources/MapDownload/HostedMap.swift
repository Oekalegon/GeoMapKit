import Foundation
import GeoCore

/// A ready-made map on a server: one `.gmk` store file for an area, built once with this kit and put where an app can download it.
/// A phone fetches a small file and does no building.
public struct HostedMap: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    /// What the map is called when it is added.
    public let name: String
    /// Where the file is.
    public let url: URL
    /// The size of the file in bytes.
    public let bytes: Int64
    /// The area the file covers.
    public let bounds: BoundingBox
    /// When the file was built from the OpenStreetMap data, if the index says.
    public let builtAt: Date?

    public init(id: String, name: String, url: URL, bytes: Int64, bounds: BoundingBox, builtAt: Date? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.bytes = bytes
        self.bounds = bounds
        self.builtAt = builtAt
    }
}
