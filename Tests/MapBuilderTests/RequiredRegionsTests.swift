import Foundation
import GeoCore
import Regions
import Testing

@testable import MapBuilder

@Suite("MapBuilder.requiredRegions")
struct RequiredRegionsTests {
    private func region(_ id: String, parent: String? = nil, west: Double, east: Double, south: Double = 40, north: Double = 44) -> SourceRegion {
        let ring = [
            Coordinate(latitude: south, longitude: west), Coordinate(latitude: south, longitude: east),
            Coordinate(latitude: north, longitude: east), Coordinate(latitude: north, longitude: west),
        ]
        return SourceRegion(
            id: id, name: id, parentID: parent, pbfURL: URL(string: "https://download.example.org/\(id).osm.pbf")!,
            outline: [RegionPolygon(outer: ring)])
    }

    @Test("A region on a border brings in the neighbour its blocks are cut from; a region far away is not needed")
    func neighbourAtBorder() throws {
        let index = try RegionIndex(regions: [
            region("a", west: 0, east: 5), region("b", west: 5, east: 10), region("far", west: 30, east: 35),
        ])
        let needed = try MapBuilder.requiredRegions(area: .regions(["a"]), in: index).map(\.id)
        #expect(needed == ["a", "b"])
    }

    @Test("A region with no neighbour needs only itself")
    func alone() throws {
        let index = try RegionIndex(regions: [region("a", west: 0, east: 5), region("far", west: 30, east: 35)])
        #expect(try MapBuilder.requiredRegions(area: .regions(["a"]), in: index).map(\.id) == ["a"])
    }

    @Test("An unknown region is an error")
    func unknown() throws {
        let index = try RegionIndex(regions: [region("a", west: 0, east: 5)])
        #expect(throws: MapBuilderError.self) { try MapBuilder.requiredRegions(area: .regions(["nope"]), in: index) }
    }
}
