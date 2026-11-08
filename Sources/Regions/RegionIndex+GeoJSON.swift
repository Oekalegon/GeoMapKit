import Foundation
import GeoCore

extension RegionIndex {
    /// Reads an index in the GeoJSON form that Geofabrik publishes (`index-v1.json`): a feature collection in which each
    /// feature has `properties` with `id`, `name`, an optional `parent` and `urls.pbf`, and a polygon or multipolygon outline
    /// of `[longitude, latitude]` points.
    ///
    /// Regions without a PBF URL are left out: there is nothing to fetch for them. Every URL must be `http` or `https`, so a
    /// bad index cannot point a download at a local file.
    ///
    /// - Parameter data: The JSON.
    /// - Throws: ``RegionError/invalidIndex(_:)`` for malformed JSON, a region with no or a bad outline (non-finite or
    ///   out-of-range coordinates, a ring of fewer than 3 vertices, a geometry that is no polygon) or a URL that is not
    ///   `http` or `https`; ``RegionError/duplicateRegion(_:)`` for a repeated ID.
    public init(geoJSON data: Data) throws {
        let collection: FeatureCollection
        do {
            collection = try JSONDecoder().decode(FeatureCollection.self, from: data)
        } catch {
            throw RegionError.invalidIndex("not a region index: \(error)")
        }
        var regions: [SourceRegion] = []
        regions.reserveCapacity(collection.features.count)
        for feature in collection.features {
            let properties = feature.properties
            guard let address = properties.urls?.pbf else { continue }
            guard let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                throw RegionError.invalidIndex("\(properties.id): the PBF address '\(address)' is not an http or https URL")
            }
            let outline = try Self.outline(of: feature, id: properties.id)
            regions.append(
                SourceRegion(id: properties.id, name: properties.name, parentID: properties.parent, pbfURL: url, outline: outline))
        }
        try self.init(regions: regions)
    }

    private static func outline(of feature: FeatureCollection.Feature, id: String) throws -> [RegionPolygon] {
        guard let geometry = feature.geometry else { throw RegionError.invalidIndex("\(id): no outline") }
        let polygons: [[[[Double]]]]
        switch geometry {
        case .polygon(let rings): polygons = [rings]
        case .multiPolygon(let all): polygons = all
        }
        func ring(_ points: [[Double]]) throws -> [Coordinate] {
            var coordinates: [Coordinate] = []
            coordinates.reserveCapacity(points.count)
            for point in points {
                guard point.count >= 2, point[0].isFinite, point[1].isFinite, abs(point[0]) <= 180, abs(point[1]) <= 90 else {
                    throw RegionError.invalidIndex("\(id): a point of the outline is not a valid longitude and latitude")
                }
                coordinates.append(Coordinate(latitude: point[1], longitude: point[0]))
            }
            // A GeoJSON ring repeats its first point at the end.
            if coordinates.count > 1, coordinates.first == coordinates.last { coordinates.removeLast() }
            guard coordinates.count >= 3 else { throw RegionError.invalidIndex("\(id): a ring has fewer than 3 vertices") }
            return coordinates
        }
        var result: [RegionPolygon] = []
        for rings in polygons {
            guard let outer = rings.first else { throw RegionError.invalidIndex("\(id): a polygon has no rings") }
            result.append(RegionPolygon(outer: try ring(outer), holes: try rings.dropFirst().map(ring)))
        }
        guard !result.isEmpty else { throw RegionError.invalidIndex("\(id): the outline has no polygon") }
        return result
    }
}

/// The parts of the GeoJSON that are read.
private struct FeatureCollection: Decodable {
    struct Properties: Decodable {
        struct URLs: Decodable { var pbf: String? }
        var id: String
        var name: String
        var parent: String?
        var urls: URLs?
    }

    enum Geometry: Decodable {
        case polygon([[[Double]]])
        case multiPolygon([[[[Double]]]])

        private enum Keys: String, CodingKey { case type, coordinates }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            switch try container.decode(String.self, forKey: .type) {
            case "Polygon": self = .polygon(try container.decode([[[Double]]].self, forKey: .coordinates))
            case "MultiPolygon": self = .multiPolygon(try container.decode([[[[Double]]]].self, forKey: .coordinates))
            case let other:
                throw DecodingError.dataCorruptedError(
                    forKey: .type, in: container, debugDescription: "the geometry is a \(other), not a Polygon or MultiPolygon")
            }
        }
    }

    struct Feature: Decodable {
        var properties: Properties
        var geometry: Geometry?
    }

    var features: [Feature]
}
