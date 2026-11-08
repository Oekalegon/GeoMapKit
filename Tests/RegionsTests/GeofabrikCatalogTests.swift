import Foundation
import Testing

@testable import Regions

/// The kept copy of the region index.
@Suite("GeofabrikCatalog")
struct GeofabrikCatalogTests {
    private let url = URL(string: "https://download.example.org/index-v1.json")!

    private func index(_ ids: [String]) -> Data {
        let features = ids.enumerated().map { number, id in
            """
            {"type":"Feature","properties":{"id":"\(id)","name":"\(id)","urls":{"pbf":"https://download.example.org/\(id).osm.pbf"}},\
            "geometry":{"type":"MultiPolygon","coordinates":[[[[\(number),0],[\(number + 1),0],[\(number + 1),1],[\(number),0]]]]}}
            """
        }
        return Data("{\"type\":\"FeatureCollection\",\"features\":[\(features.joined(separator: ","))]}".utf8)
    }

    private struct Setup {
        let catalog: GeofabrikCatalog
        let server: FakeServer
        let clock: TestClock
        let directory: URL
    }

    private func setup(_ ids: [String] = ["norway", "sweden"]) async -> Setup {
        let server = FakeServer()
        await server.put(url, index(ids), etag: "\"i1\"")
        let clock = TestClock()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-catalog-\(UUID().uuidString)")
        let catalog = GeofabrikCatalog(directory: directory, downloader: FakeDownloader(server: server), url: url, now: { clock.now })
        return Setup(catalog: catalog, server: server, clock: clock, directory: directory)
    }

    @Test("The first call downloads the index; within 30 days the copy is used without asking the server")
    func firstThenCached() async throws {
        let s = await setup()
        defer { try? FileManager.default.removeItem(at: s.directory) }
        #expect(try await s.catalog.index().regions.map(\.id) == ["norway", "sweden"])
        let asked = await s.server.requests(containing: "").count
        s.clock.advance(days: 29)
        #expect(try await s.catalog.index().regions.count == 2)
        #expect(await s.server.requests(containing: "").count == asked)
    }

    @Test("After 30 days the server is asked with the ETag: unchanged renews the check, changed is downloaded")
    func renewal() async throws {
        let s = await setup()
        defer { try? FileManager.default.removeItem(at: s.directory) }
        _ = try await s.catalog.index()
        s.clock.advance(days: 31)
        #expect(try await s.catalog.index().regions.count == 2)
        #expect(await s.server.requests(containing: "if-none-match \"i1\"").count == 1)
        #expect(await s.server.requests(containing: "GET").count == 1, "not downloaded again")
        // The check was recorded.
        let asked = await s.server.requests(containing: "HEAD").count
        _ = try await s.catalog.index()
        #expect(await s.server.requests(containing: "HEAD").count == asked)

        await s.server.put(url, index(["norway", "sweden", "finland"]), etag: "\"i2\"")
        s.clock.advance(days: 31)
        #expect(try await s.catalog.index().regions.map(\.id) == ["norway", "sweden", "finland"])
    }

    @Test("Without a network the copy is used; without a copy the error is raised")
    func offline() async throws {
        let s = await setup()
        defer { try? FileManager.default.removeItem(at: s.directory) }
        await s.server.setOffline(true)
        await #expect(throws: (any Error).self) { try await s.catalog.index() }
        await s.server.setOffline(false)
        _ = try await s.catalog.index()
        s.clock.advance(days: 90)
        await s.server.setOffline(true)
        #expect(try await s.catalog.index().regions.count == 2)
    }

    @Test("A new index that is not valid never replaces a good copy")
    func invalidReplacement() async throws {
        let s = await setup()
        defer { try? FileManager.default.removeItem(at: s.directory) }
        _ = try await s.catalog.index()
        await s.server.put(url, Data("<html>maintenance</html>".utf8), etag: "\"i2\"")
        s.clock.advance(days: 31)
        #expect(try await s.catalog.index().regions.map(\.id) == ["norway", "sweden"])
        // And with no copy at all the bad index is an error.
        try FileManager.default.removeItem(at: s.directory)
        await #expect(throws: RegionError.self) { try await s.catalog.index() }
    }

    @Test("A copy that cannot be read is downloaded again")
    func damagedCopy() async throws {
        let s = await setup()
        defer { try? FileManager.default.removeItem(at: s.directory) }
        _ = try await s.catalog.index()
        try Data("broken".utf8).write(to: s.directory.appendingPathComponent("geofabrik-index-v1.json"))
        #expect(try await s.catalog.index().regions.count == 2)
        #expect(await s.server.requests(containing: "GET").count == 2)
    }
}
