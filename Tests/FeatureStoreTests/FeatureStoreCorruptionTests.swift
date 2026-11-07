import Foundation
import GeoCore
import Testing

@testable import FeatureStore

/// A damaged file must fail with an error or read as garbage, and never crash.
@Suite("Feature store corruption")
struct FeatureStoreCorruptionTests {
    private let cell = TileID(zoom: 13, x: 4_285, y: 2_850)!

    private func validBytes() throws -> Data {
        var writer = FeatureStoreWriter(boundingBox: BoundingBox(south: 47, west: 9, north: 48, east: 10), attribution: "OSM")
        let key = writer.intern("highway"), value = writer.intern("path")
        let part = GeometryPart(points: (0..<20).map { PackedPoint(longitude: 95_000_000 + Int32($0 * 10), latitude: 470_000_000 + Int32($0 * $0)) }, artificialEdges: [2..<4])
        for band in ZoomBand.allCases {
            try writer.add(StoredFeature(classID: 2, kind: .line, objectType: .way, objectID: 10, nameID: value,
                tags: [StoredTag(key: key, value: value)], parts: [part]), band: band, cell: cell)
        }
        try writer.add(StoredRelation(id: 3, tags: [StoredTag(key: key, value: value)],
            members: [StoredRelationMember(type: .way, id: 10, role: key)]))
        return try writer.data()
    }

    @Test("An empty file and a wrong magic are rejected")
    func magic() throws {
        #expect(throws: FeatureStoreError.truncated) { try FeatureStoreFile(data: Data()) }
        var bytes = try validBytes()
        bytes[0] = 0x58
        #expect(throws: FeatureStoreError.badMagic) { try FeatureStoreFile(data: bytes) }
        #expect(throws: FeatureStoreError.badMagic) { try FeatureStoreFile(data: Data("hello, this is not a store".utf8)) }
    }

    @Test("A newer format version is rejected")
    func wrongVersion() throws {
        var bytes = try validBytes()
        bytes[4] = 2
        #expect(throws: FeatureStoreError.unsupportedVersion(2)) { try FeatureStoreFile(data: bytes) }
    }

    @Test("Every truncation is rejected when opening")
    func truncation() throws {
        let bytes = try validBytes()
        for length in 0..<bytes.count {
            #expect(throws: FeatureStoreError.self, "length \(length)") { try FeatureStoreFile(data: bytes.prefix(length)) }
        }
    }

    @Test("Extra bytes at the end are rejected")
    func trailingBytes() throws {
        let bytes = try validBytes() + Data([0])
        #expect(throws: FeatureStoreError.self) { try FeatureStoreFile(data: bytes) }
    }

    @Test("Any flipped byte is caught by verify")
    func checksum() throws {
        let bytes = try validBytes()
        for position in 0..<bytes.count {
            var damaged = bytes
            damaged[position] ^= 0x55
            guard let file = try? FeatureStoreFile(data: damaged) else { continue }
            #expect(throws: FeatureStoreError.self, "byte \(position)") { try file.verify() }
        }
    }

    @Test("Reading damaged cells never crashes, even without the checksum")
    func damagedReadsAreSafe() throws {
        let bytes = try validBytes()
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<3_000 {
            var damaged = bytes
            for _ in 0..<Int.random(in: 1...4, using: &generator) {
                damaged[Int.random(in: 0..<damaged.count, using: &generator)] = UInt8.random(in: 0...255, using: &generator)
            }
            guard let file = try? FeatureStoreFile(data: damaged) else { continue }
            for band in ZoomBand.allCases { _ = try? file.features(in: cell, band: band) }
            _ = try? file.relation(withID: 3)
            _ = try? file.cells()
            _ = file.string(at: 0)
            _ = try? file.verify()
        }
    }

    @Test("A string ID outside the table reads as nil")
    func stringOutOfRange() throws {
        let file = try FeatureStoreFile(data: try validBytes())
        #expect(file.string(at: 1_000) == nil)
    }
}
