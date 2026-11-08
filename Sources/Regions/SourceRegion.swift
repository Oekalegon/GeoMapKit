import Foundation
import GeoCore

/// A region that has a source file: a country, a state or a larger area, as listed in the region index.
public struct SourceRegion: Hashable, Sendable {
    /// The identifier in the index, for example `norway`; unique in an index.
    public let id: String
    /// The name to show, for example `Norway`.
    public let name: String
    /// The identifier of the region this one is part of, or `nil` for a continent.
    public let parentID: String?
    /// Where the PBF file of the region is published (`http` or `https`).
    public let pbfURL: URL
    /// The outline of the region. It is simplified: good for deciding which regions an area lies in, not for drawing.
    public let outline: [RegionPolygon]
    /// The smallest box that contains the outline.
    public let boundingBox: BoundingBox
    /// The size of the outline for ordering regions, see ``RegionPolygon/approximateArea``.
    public let approximateArea: Double

    /// Creates a region. The bounding box and the area are worked out from the outline.
    ///
    /// - Parameters:
    ///   - id: The identifier.
    ///   - name: The name to show.
    ///   - parentID: The identifier of the parent region, if any.
    ///   - pbfURL: The URL of the PBF file.
    ///   - outline: The polygons of the outline, at least one.
    public init(id: String, name: String, parentID: String?, pbfURL: URL, outline: [RegionPolygon]) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.pbfURL = pbfURL
        self.outline = outline
        let points = outline.flatMap(\.outer)
        boundingBox = BoundingBox(
            south: points.map(\.latitude).min() ?? 0, west: points.map(\.longitude).min() ?? 0,
            north: points.map(\.latitude).max() ?? 0, east: points.map(\.longitude).max() ?? 0)
        approximateArea = outline.reduce(0) { $0 + $1.approximateArea }
    }

    /// Whether a coordinate lies inside the outline.
    ///
    /// - Parameter coordinate: The position to test.
    public func contains(_ coordinate: Coordinate) -> Bool {
        boundingBox.contains(coordinate) && outline.contains { $0.contains(coordinate) }
    }
}
