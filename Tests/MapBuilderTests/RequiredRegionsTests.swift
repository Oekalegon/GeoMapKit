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
            region("a", west: 0, east: 5.4), region("b", west: 5.4, east: 10), region("far", west: 30, east: 35),
        ])
        let needed = try MapBuilder.requiredRegions(area: .regions(["a"]), in: index).map(\.id)
        #expect(needed == ["a", "b"])
    }

    @Test("A neighbour the user skips is not planned, but a selected region cannot be skipped")
    func skippedNeighbour() throws {
        let index = try RegionIndex(regions: [region("a", west: 0, east: 5.4), region("b", west: 5.4, east: 10)])
        #expect(try MapBuilder.requiredRegions(area: .regions(["a"]), in: index, skipping: ["b"]).map(\.id) == ["a"])
        #expect(try MapBuilder.requiredRegions(area: .regions(["a"]), in: index, skipping: ["a"]).map(\.id) == ["a", "b"])
        let tasks = try MapBuilder.plannedBlocks(area: .regions(["a"]), blockZoom: 8, margin: 0.1, in: index, skipping: ["b"])
        #expect(tasks.contains { $0.leftOut.contains { $0.id == "b" } })
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
        let home = region("home", west: 8, east: 11, south: 46, north: 49)
        let next = region("sud", parent: "land", west: 11, east: 14, south: 46, north: 49)
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
            region("a", west: 0, east: 5.4), region("b", west: 10, east: 15), region("mid", west: 5.4, east: 10),
        ])
        let needed = try MapBuilder.requiredRegions(area: .regions(["a", "b"]), in: index).map(\.id)
        #expect(needed == ["a", "b", "mid"])
    }
}

@Suite("MapBuilder.requiredRegions: one file for the same ground")
struct SettledRegionsTests {
    private func region(_ id: String, parent: String? = nil, west: Double, east: Double, south: Double = 40, north: Double = 44) -> SourceRegion {
        let ring = [
            Coordinate(latitude: south, longitude: west), Coordinate(latitude: south, longitude: east),
            Coordinate(latitude: north, longitude: east), Coordinate(latitude: north, longitude: west),
        ]
        return SourceRegion(
            id: id, name: id, parentID: parent, pbfURL: URL(string: "https://download.example.org/\(id).osm.pbf")!,
            outline: [RegionPolygon(outer: ring)])
    }

    private func held(_ ids: [String]) throws -> (SourceCache, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-settle-\(UUID().uuidString)")
        let cache = SourceCache(directory: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for id in ids {
            let part = try cache.preparePart(regionID: id, etag: "\"e\"", keepBytes: false)
            try Data("x".utf8).write(to: part)
            try cache.install(
                regionID: id, from: URL(string: "https://download.example.org/\(id).osm.pbf")!,
                info: RemoteFileInfo(size: 1, etag: "\"e\"", lastModified: "Mon"))
        }
        return (cache, root)
    }

    /// Spain (0 to 10) with two parts, a neighbour country east of it, and a continent that covers a gap between neighbour outlines.
    private func world() throws -> RegionIndex {
        try RegionIndex(regions: [
            region("spain", parent: "europe", west: 0, east: 10), region("south", parent: "spain", west: 0, east: 5),
            region("north", parent: "spain", west: 5, east: 10), region("europe", west: -5, east: 30),
            region("pt", parent: "europe", west: 10, east: 14), region("rest", parent: "europe", west: 14, east: 18),
        ])
    }

    @Test("A selected region is the source of its blocks; its parts are not planned")
    func selectedWins() throws {
        let needed = try MapBuilder.requiredRegions(area: .regions(["spain"]), in: try world()).map(\.id)
        #expect(needed.contains("spain") && !needed.contains("south") && !needed.contains("north"))
    }

    @Test("A parent and a part of it are never planned together")
    func noParentWithPart() throws {
        let index = try world()
        let needed = try MapBuilder.requiredRegions(area: .regions(["pt"]), in: index).map(\.id)
        #expect(!(needed.contains("europe") && needed.contains("south")))
        #expect(!(needed.contains("spain") && needed.contains("south")))
    }

    @Test("A held file stands in for a part of it that is not held")
    func heldParentCovers() throws {
        let (cache, root) = try held(["spain", "pt"])
        defer { try? FileManager.default.removeItem(at: root) }
        let needed = try MapBuilder.requiredRegions(area: .regions(["pt"]), in: try world(), cache: cache).map(\.id)
        #expect(needed.contains("spain") && !needed.contains("north") && !needed.contains("south"))
    }

    @Test("A part that is held is used itself, not its parent")
    func heldPartStays() throws {
        let (cache, root) = try held(["spain", "north", "pt"])
        defer { try? FileManager.default.removeItem(at: root) }
        let needed = try MapBuilder.requiredRegions(area: .regions(["pt"]), in: try world(), cache: cache).map(\.id)
        #expect(needed.contains("north") && !needed.contains("spain"))
    }

    @Test("A selected region that is not held, with parts that are, is not downloaded: the parts are used")
    func selectedNotHeldPartsHeld() throws {
        let (cache, root) = try held(["south", "north"])
        defer { try? FileManager.default.removeItem(at: root) }
        let needed = try MapBuilder.requiredRegions(area: .regions(["spain"]), in: try world(), cache: cache).map(\.id)
        #expect(needed.contains("south") && needed.contains("north") && !needed.contains("spain"))
    }

    @Test("A held ancestor much larger than the part is not a source for it")
    func hugeAncestor() throws {
        let index = try RegionIndex(regions: [
            region("europe", west: -50, east: 50, south: 0, north: 80), region("a", parent: "europe", west: 0, east: 5.4),
            region("b", parent: "europe", west: 5.4, east: 6.4, south: 40, north: 41),
        ])
        let (cache, root) = try held(["europe", "a"])
        defer { try? FileManager.default.removeItem(at: root) }
        let needed = try MapBuilder.requiredRegions(area: .regions(["a"]), in: index, cache: cache).map(\.id)
        #expect(needed.contains("b") && !needed.contains("europe"))
    }

    @Test("An aggregate outside the tree goes when the parts of the block hold all it holds there")
    func aggregateRedundant() throws {
        let index = try RegionIndex(regions: [
            region("home", parent: "europe", west: 0, east: 5), region("next", parent: "europe", west: 5, east: 10),
            region("europe", west: -50, east: 50, south: 0, north: 80), region("group", west: 0, east: 10),
        ])
        let needed = try MapBuilder.requiredRegions(area: .regions(["home"]), in: index).map(\.id)
        #expect(!needed.contains("group"))
    }

    @Test("A neighbour that only reaches the margin of the cut is not read; one that holds ground of the tile stays")
    func marginOnlyNeighbour() throws {
        // The tiles of zoom 8 end at 5.625 degrees of longitude: "a" ends there, so "next" is in the margin of the cut only.
        let index = try RegionIndex(regions: [region("a", west: 0, east: 5.625), region("next", west: 5.625, east: 10)])
        #expect(try MapBuilder.requiredRegions(area: .regions(["a"]), in: index).map(\.id) == ["a"])
        let shared = try RegionIndex(regions: [region("a", west: 0, east: 5.4), region("next", west: 5.4, east: 10)])
        #expect(try MapBuilder.requiredRegions(area: .regions(["a"]), in: shared).map(\.id).contains("next"))
    }

    @Test("A block that lies mostly outside the selection brings in no neighbour: the Channel does not need Britain")
    func mostlyForeignBlock() throws {
        // "home" covers 3 of the 5.6 degrees of the tile at 4.2 to 5.6: under 75 %, so the neighbour that holds the rest is not read.
        let index = try RegionIndex(regions: [region("home", west: 0, east: 4.9), region("next", west: 4.9, east: 10)])
        #expect(try MapBuilder.requiredRegions(area: .regions(["home"]), in: index).map(\.id) == ["home"])
    }

    @Test("Without a selected region (a box or tiles) the neighbours are as before")
    func boxKeepsNeighbours() throws {
        let index = try RegionIndex(regions: [region("a", west: 0, east: 4.9), region("next", west: 4.9, east: 10)])
        let box = BoundingBox(south: 41, west: 4.3, north: 42, east: 5.5)
        let needed = try MapBuilder.requiredRegions(area: .box(box), in: index).map(\.id)
        #expect(needed.contains("a") && needed.contains("next"))
    }

    @Test("Several selected regions count together: a neighbour stays where they hold most of the tile, and goes with one of them alone")
    func severalSelected() throws {
        // At the tile of 9.84 to 11.25 degrees "a" holds 26 %, "a" with "b" 83 %; "c" holds ground there that neither has.
        let index = try RegionIndex(regions: [
            region("a", west: 0, east: 10.2), region("b", west: 10.2, east: 11), region("c", west: 10.5, east: 12),
        ])
        #expect(!(try MapBuilder.requiredRegions(area: .regions(["a"]), in: index).map(\.id).contains("c")))
        #expect(try MapBuilder.requiredRegions(area: .regions(["a", "b"]), in: index).map(\.id).contains("c"))
    }

    @Test("The parts of a selected region count as the selection, and the neighbours that are left out are listed on the block")
    func partsAreOwn() throws {
        let tasks = try MapBuilder.plannedBlocks(area: .regions(["spain"]), blockZoom: 8, margin: 0.1, in: try world())
        let ids = Set(tasks.flatMap { $0.regions.map(\.id) })
        #expect(ids.contains("spain") && !ids.contains("pt"), "pt holds ground only in the one tile that is mostly pt's")
        #expect(tasks.contains { $0.leftOut.contains { $0.id == "pt" } })
    }

    @Test("A build reads the files that the plan names: it needs no neighbour that was left out, and says that it built without it")
    func buildWithoutLeftOutNeighbour() async throws {
        let home = region("home", west: 8, east: 10.5, south: 46, north: 49)
        let next = region("sud", west: 10.5, east: 14, south: 46, north: 49)
        let index = try RegionIndex(regions: [home, next])
        #expect(try MapBuilder.requiredRegions(area: .regions(["home"]), in: index).map(\.id) == ["home"])

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-leftout-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = SourceCache(directory: root.appendingPathComponent("cache"))
        struct Fixed: RegionCatalog {
            let index: RegionIndex
            func index() async throws -> RegionIndex { index }
        }
        let part = try cache.preparePart(regionID: "home", etag: "\"e\"", keepBytes: false)
        try TinyPBF.make().write(to: part)
        try cache.install(
            regionID: "home", from: URL(string: "https://download.example.org/home.osm.pbf")!,
            info: RemoteFileInfo(size: Int64(try TinyPBF.make().count), etag: "\"e\"", lastModified: "Mon"))
        let request = BlockRequest(area: .regions(["home"]), output: root.appendingPathComponent("out"), cacheDirectory: cache.directory)
        let report = try await MapBuilder.buildRegion(request, catalog: Fixed(index: index))
        #expect(report.warnings.contains { $0.contains("without sud") })
    }
}
