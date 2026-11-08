import Foundation
import GeoCore
import Testing

@testable import Regions

/// Reading a region index and choosing the regions for an area.
@Suite("RegionIndex")
struct RegionIndexTests {
    /// One feature: a rectangle from (west, south) to (east, north).
    private func feature(
        _ id: String, parent: String? = nil, pbf: String? = nil, west: Double, south: Double, east: Double, north: Double,
        geometry: String? = nil
    ) -> String {
        let address = pbf ?? "https://download.example.org/\(id)-latest.osm.pbf"
        let ring = "[[\(west),\(south)],[\(east),\(south)],[\(east),\(north)],[\(west),\(north)],[\(west),\(south)]]"
        return """
            {"type":"Feature","properties":{"id":"\(id)","name":"\(id.capitalized)",\(parent.map { "\"parent\":\"\($0)\"," } ?? "")\
            "urls":{\(address.isEmpty ? "" : "\"pbf\":\"\(address)\"")}},\
            "geometry":\(geometry ?? "{\"type\":\"MultiPolygon\",\"coordinates\":[[\(ring)]]}")}
            """
    }

    private func json(_ features: [String]) -> Data {
        Data("{\"type\":\"FeatureCollection\",\"features\":[\(features.joined(separator: ","))]}".utf8)
    }

    /// Europe, with Norway and its south-east part, Sweden east of it, and two small countries `a` and `b` with an aggregate
    /// `ab` that is larger than each and reaches further east than both.
    private func world() throws -> RegionIndex {
        try RegionIndex(geoJSON: json([
            feature("europe", west: -20, south: 30, east: 40, north: 75),
            feature("norway", parent: "europe", west: 4, south: 58, east: 12, north: 70),
            feature("ostlandet", parent: "norway", west: 8, south: 58, east: 12, north: 62),
            feature("sweden", parent: "europe", west: 12, south: 55, east: 24, north: 69),
            feature("a", parent: "europe", west: 30, south: 40, east: 34, north: 44),
            feature("b", parent: "europe", west: 34, south: 40, east: 38, north: 44),
            feature("ab", parent: "europe", west: 30, south: 40, east: 40, north: 44),
        ]))
    }

    private func ids(_ selection: RegionSelection) -> [String] { selection.regions.map(\.id) }

    private func box(_ west: Double, _ south: Double, _ east: Double, _ north: Double) -> BoundingBox {
        BoundingBox(south: south, west: west, north: north, east: east)
    }

    // MARK: Reading

    @Test("The index is read with names, parents, URLs and outlines; a region without a PBF file is left out")
    func reading() throws {
        let index = try RegionIndex(geoJSON: json([
            feature("europe", west: -20, south: 30, east: 40, north: 75),
            feature("norway", parent: "europe", west: 4, south: 58, east: 12, north: 70),
            feature("nofile", parent: "europe", pbf: "", west: 0, south: 0, east: 1, north: 1),
        ]))
        #expect(index.regions.map(\.id) == ["europe", "norway"])
        let norway = try #require(index.region(withID: "norway"))
        #expect(norway.name == "Norway" && norway.parentID == "europe")
        #expect(norway.pbfURL.absoluteString == "https://download.example.org/norway-latest.osm.pbf")
        #expect(norway.boundingBox == box(4, 58, 12, 70))
        #expect(norway.outline.count == 1 && norway.outline[0].outer.count == 4, "the closing point is not stored")
        #expect(norway.contains(Coordinate(latitude: 65, longitude: 8)) && !norway.contains(Coordinate(latitude: 65, longitude: 13)))
        #expect(index.region(withID: "nofile") == nil)
        #expect(try world().region("ostlandet", isBelow: "europe"))
        #expect(try !world().region("europe", isBelow: "ostlandet"))
    }

    @Test("A polygon with a hole does not contain the hole, and a Polygon geometry is read like a MultiPolygon")
    func holes() throws {
        let polygon = """
            {"type":"Polygon","coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]],[[4,4],[6,4],[6,6],[4,6],[4,4]]]}
            """
        let index = try RegionIndex(geoJSON: json([feature("ring", west: 0, south: 0, east: 10, north: 10, geometry: polygon)]))
        let region = try #require(index.region(withID: "ring"))
        #expect(region.contains(Coordinate(latitude: 2, longitude: 2)) && !region.contains(Coordinate(latitude: 5, longitude: 5)))
        #expect(abs(region.approximateArea - 96 * cos(5 * .pi / 180)) < 1e-6, "100 minus the hole of 4, scaled by the latitude")
    }

    @Test("A bad index is refused with a reason")
    func badIndexes() throws {
        func fails(_ data: Data) -> Bool {
            do { _ = try RegionIndex(geoJSON: data); return false } catch is RegionError { return true } catch { return false }
        }
        #expect(fails(Data("not json".utf8)))
        #expect(fails(Data("{\"type\":\"FeatureCollection\"}".utf8)), "no features")
        let line = "{\"type\":\"LineString\",\"coordinates\":[[0,0],[1,1]]}"
        #expect(fails(json([feature("x", west: 0, south: 0, east: 1, north: 1, geometry: line)])), "not a polygon")
        #expect(fails(json([feature("x", pbf: "file:///etc/passwd", west: 0, south: 0, east: 1, north: 1)])), "a file URL")
        #expect(fails(json([feature("x", pbf: "ftp://example.org/x.pbf", west: 0, south: 0, east: 1, north: 1)])))
        #expect(fails(json([feature("x", west: 0, south: 0, east: 1, north: 1), feature("x", west: 2, south: 0, east: 3, north: 1)])))
        let far = "{\"type\":\"MultiPolygon\",\"coordinates\":[[[[0,0],[200,0],[200,10],[0,0]]]]}"
        #expect(fails(json([feature("x", west: 0, south: 0, east: 1, north: 1, geometry: far)])), "longitude out of range")
        let short = "{\"type\":\"MultiPolygon\",\"coordinates\":[[[[0,0],[1,1],[0,0]]]]}"
        #expect(fails(json([feature("x", west: 0, south: 0, east: 1, north: 1, geometry: short)])), "a ring of two points")
        let empty = "{\"type\":\"MultiPolygon\",\"coordinates\":[]}"
        #expect(fails(json([feature("x", west: 0, south: 0, east: 1, north: 1, geometry: empty)])))
    }

    @Test("A parent cycle in the index does not hang the tree test")
    func cycle() throws {
        let index = try RegionIndex(geoJSON: json([
            feature("p", parent: "q", west: 0, south: 0, east: 1, north: 1), feature("q", parent: "p", west: 0, south: 0, east: 1, north: 1),
        ]))
        #expect(!index.region("p", isBelow: "other"))
    }

    // MARK: Choosing

    @Test("An area inside one region gets that region, and not the larger ones that contain it")
    func smallestRegion() throws {
        let selection = try world().regions(covering: box(9, 59, 11, 61))
        #expect(ids(selection) == ["ostlandet"] && selection.coveredShare == 1)
        #expect(ids(try world().regions(covering: box(5, 64, 9, 68))) == ["norway"])
    }

    @Test("An area on a border gets both sides, the one that covers most first")
    func border() throws {
        let selection = try world().regions(covering: box(10.5, 59, 13, 61))
        #expect(ids(selection) == ["ostlandet", "sweden"])
        #expect(selection.coveredShare == 1)
        #expect(ids(try world().regions(covering: box(11, 59, 14, 61))) == ["sweden", "ostlandet"], "now Sweden covers more")
    }

    @Test("An aggregate larger than its parts is not used where the parts cover the area, but is where they do not")
    func aggregate() throws {
        let parts = try world().regions(covering: box(33, 41, 35, 43))
        #expect(Set(ids(parts)) == ["a", "b"] && parts.coveredShare == 1)
        #expect(ids(try world().regions(covering: box(38.5, 41, 39.5, 43))) == ["ab"], "only the aggregate reaches this far east")
    }

    @Test("Ground that only a parent covers is not added once a child is chosen, and the share says so")
    func parentOnlyGround() throws {
        // Lower half in Ostlandet, upper half in Norway outside it: the parent's outline also covers sea, so it is not added.
        let selection = try world().regions(covering: box(8.5, 60, 11.5, 64))
        #expect(ids(selection) == ["ostlandet"])
        #expect(abs(selection.coveredShare - 0.5) < 0.05)
    }

    @Test("The number of regions is limited, and nothing is returned for an invalid area or an area nobody covers")
    func limits() throws {
        #expect(try world().regions(covering: box(10.5, 59, 13, 61), maximumRegions: 1).regions.count == 1)
        #expect(try world().regions(covering: BoundingBox(south: 5, west: 5, north: 1, east: 1)) == RegionSelection(regions: [], coveredShare: 0))
        let nowhere = try world().regions(covering: box(100, 10, 101, 11))
        #expect(nowhere.regions.isEmpty && nowhere.coveredShare == 0)
    }

    // MARK: The real index

    /// With the Geofabrik index saved as a file (`curl -O https://download.geofabrik.de/index-v1.json`), set
    /// `GEOMAPKIT_REGION_INDEX` to its path. Without it this test is skipped, as it is on CI.
    @Test(
        "The real Geofabrik index gives the regions of Halden, Liechtenstein and Troms",
        .enabled(if: ProcessInfo.processInfo.environment["GEOMAPKIT_REGION_INDEX"] != nil))
    func realIndex() throws {
        let path = try #require(ProcessInfo.processInfo.environment["GEOMAPKIT_REGION_INDEX"])
        let index = try RegionIndex(geoJSON: Data(contentsOf: URL(fileURLWithPath: path)))
        #expect(index.regions.count > 400)
        #expect(ids(index.regions(covering: box(11.2, 59.0, 11.6, 59.25))) == ["ostlandet", "sweden"])
        #expect(Set(ids(index.regions(covering: box(9.45, 47.0, 9.65, 47.3)))) == ["liechtenstein", "switzerland", "austria"])
        #expect(ids(index.regions(covering: box(18.5, 69.5, 19.5, 69.8))) == ["nord-norge"])
        #expect(index.regions(covering: box(11.2, 59.0, 11.6, 59.25)).coveredShare > 0.99)
    }
}
