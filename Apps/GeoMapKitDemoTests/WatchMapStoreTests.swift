import FeatureStore
import Foundation
import GeoCore
import Testing

@testable import GeoMapKitDemo

@Suite("Watch maps")
struct WatchMapStoreTests {
    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-watch-\(UUID().uuidString)", isDirectory: true)
    }

    /// A small valid store file in a folder of its own.
    private func makeStore(in directory: URL, named name: String = "incoming.gmk", north: Double = 60) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var writer = FeatureStoreWriter(boundingBox: BoundingBox(south: 59, west: 10, north: north, east: 11), attribution: "x")
        let cell = try #require(TileID(zoom: 13, x: 4_300, y: 2_300))
        try writer.add(
            StoredFeature(
                classID: FeatureClass.peak.rawValue, kind: .point, objectType: .node, objectID: 1,
                parts: [GeometryPart(points: [PackedPoint(longitude: 100_000_000, latitude: 595_000_000)])]),
            band: .mid, cell: cell)
        let url = directory.appendingPathComponent(name)
        try writer.write(to: url)
        return url
    }

    @Test func aNameBecomesAFileNameHere() {
        #expect(WatchMapStore.fileName(for: "Halden") == "Halden.gmk")
        #expect(WatchMapStore.fileName(for: "Halden.gmk") == "Halden.gmk")
        #expect(WatchMapStore.fileName(for: "a/b:c") == "a-b-c.gmk")
        #expect(WatchMapStore.fileName(for: "  ..hidden ") == "hidden.gmk")
        #expect(WatchMapStore.fileName(for: "") == "Map.gmk")
        #expect(WatchMapStore.fileName(for: String(repeating: "x", count: 300)).count == 84)
    }

    @Test func aMapThatArrivesIsCheckedMovedAndListed() throws {
        let root = folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WatchMapStore(directory: root.appendingPathComponent("Maps"))
        let incoming = try makeStore(in: root.appendingPathComponent("tmp"))
        let entry = try store.accept(incoming, named: "Halden Watch 6 km")
        #expect(entry.name == "Halden Watch 6 km" && entry.id == "Halden Watch 6 km.gmk" && entry.bytes > 0)
        #expect(!FileManager.default.fileExists(atPath: incoming.path), "the file was moved")
        #expect(store.list().map(\.id) == ["Halden Watch 6 km.gmk"])
        // It opens, and the map starts in the middle of its box.
        let file = try FeatureStoreFile(contentsOf: entry.url)
        let start = WatchMapStore.start(of: file)
        #expect(abs(start.center.latitude - 59.5) < 1e-9 && abs(start.center.longitude - 10.5) < 1e-9 && start.zoom == 13)
    }

    @Test func aNewCopyUnderTheSameNameReplacesTheOldOne() throws {
        let root = folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WatchMapStore(directory: root.appendingPathComponent("Maps"))
        try store.accept(makeStore(in: root.appendingPathComponent("a"), north: 60), named: "M")
        let second = try store.accept(makeStore(in: root.appendingPathComponent("b"), north: 61), named: "M")
        #expect(store.list().count == 1)
        #expect(try FeatureStoreFile(contentsOf: second.url).boundingBox.north == 61)
    }

    @Test func aDamagedFileIsRefusedAndDeleted() throws {
        let root = folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WatchMapStore(directory: root.appendingPathComponent("Maps"))
        let good = try makeStore(in: root.appendingPathComponent("tmp"))
        var bytes = try Data(contentsOf: good)
        bytes[bytes.count / 2] ^= 0xFF
        try bytes.write(to: good)
        #expect(throws: WatchMapStoreError.self) { try store.accept(good, named: "Broken") }
        #expect(!FileManager.default.fileExists(atPath: good.path) && store.list().isEmpty)
        let text = root.appendingPathComponent("tmp/not-a-map.gmk")
        try Data("hello".utf8).write(to: text)
        #expect(throws: WatchMapStoreError.self) { try store.accept(text, named: "Text") }
    }

    @Test func aMapCanBeDeleted() throws {
        let root = folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WatchMapStore(directory: root.appendingPathComponent("Maps"))
        let entry = try store.accept(makeStore(in: root.appendingPathComponent("tmp")), named: "M")
        try store.delete(entry)
        #expect(store.list().isEmpty)
    }
}

@Suite("Watch link")
@MainActor
struct WatchLinkTests {
    @Test func aSendThatTheLinkCannotMakeIsRefusedWithASentence() throws {
        let link = WatchLink(store: WatchMapStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("x-\(UUID().uuidString)")))
        // No Watch is paired in a test: the status is never ready.
        #expect(link.status != .ready)
        #expect(throws: WatchSendError.self) { try link.send(URL(fileURLWithPath: "/nonexistent.gmk"), named: "M") }
        #expect(WatchSendError.notReady(.notPaired).localizedDescription == "No Apple Watch is paired.")
        #expect(WatchSendError.tooLarge(bytes: 200_000_000, limit: 100_000_000).localizedDescription.contains("Cut a smaller area"))
    }
}
