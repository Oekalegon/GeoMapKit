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

    @Test("The files of requiredRegions are what the build reads: with them it builds, without one it names it with its parent")
    func planEqualsBuild() async throws {
        let parent = SourceRegion(
            id: "land", name: "Land", parentID: nil, pbfURL: URL(string: "https://download.example.org/land.osm.pbf")!,
            outline: [RegionPolygon(outer: [
                Coordinate(latitude: 0, longitude: 100), Coordinate(latitude: 0, longitude: 101),
                Coordinate(latitude: 1, longitude: 101), Coordinate(latitude: 1, longitude: 100)])])
        let home = region("home", west: 8, east: 10.5, south: 46, north: 49)
        let next = region("sud", parent: "land", west: 10.5, east: 14, south: 46, north: 49)
        let index = try RegionIndex(regions: [parent, home, next])
        let needed = try MapBuilder.requiredRegions(area: .regions(["home"]), in: index)
        #expect(needed.map(\.id) == ["home", "sud"])

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-required-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = SourceCache(directory: root.appendingPathComponent("cache"))
        struct Fixed: RegionCatalog {
            let index: RegionIndex
            func index() async throws -> RegionIndex { index }
        }
        let data = try TinyPBF.make()
        func install(_ id: String) throws {
            let part = try cache.preparePart(regionID: id, etag: "\"e\"", keepBytes: false)
            try data.write(to: part)
            try cache.install(
                regionID: id, from: URL(string: "https://download.example.org/\(id).osm.pbf")!,
                info: RemoteFileInfo(size: Int64(data.count), etag: "\"e\"", lastModified: "Mon"))
        }
        let request = BlockRequest(area: .regions(["home"]), output: root.appendingPathComponent("out"), cacheDirectory: cache.directory)

        try install("home")
        do {
            _ = try await MapBuilder.buildRegion(request, catalog: Fixed(index: index))
            Issue.record("the build should name the missing neighbour")
        } catch {
            #expect("\(error)".contains("sud in Land (sud)") && "\(error)".contains("not in the cache"))
        }
        try install("sud")
        _ = try await MapBuilder.buildRegion(request, catalog: Fixed(index: index))
    }

    @Test("A neighbour of two selected regions appears once")
    func sharedNeighbour() throws {
        let index = try RegionIndex(regions: [
            region("a", west: 0, east: 5), region("b", west: 10, east: 15), region("mid", west: 5, east: 10),
        ])
        let needed = try MapBuilder.requiredRegions(area: .regions(["a", "b"]), in: index).map(\.id)
        #expect(needed == ["a", "b", "mid"])
    }
}
