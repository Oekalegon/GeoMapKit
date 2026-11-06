import Foundation
import Testing
@testable import OSMPBF

/// A malformed file must fail with a specific error, never crash and never
/// produce partial data.
@Suite("PBF corruption")
struct PBFCorruptionTests {
    private func readAll(_ data: Data) throws {
        try PBFReader(data: data).forEachBlock { _ in }
    }

    private func validFile(dataPayload: Data? = nil) -> PBFFileBuilder {
        var builder = PBFFileBuilder()
        builder.appendBlob(type: "OSMHeader", payload: PBFFileBuilder.headerPayload())
        if let dataPayload { builder.appendBlob(type: "OSMData", payload: dataPayload) }
        return builder
    }

    @Test("An empty file has no header")
    func emptyFile() {
        #expect(throws: PBFError.missingHeader) { try self.readAll(Data()) }
        #expect(throws: PBFError.missingHeader) { _ = try PBFReader(data: Data()).header() }
    }

    @Test("A file that starts with a data blob has no header")
    func dataBeforeHeader() {
        var builder = PBFFileBuilder()
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(strings: [""]))
        #expect(throws: PBFError.missingHeader) { try self.readAll(builder.file) }
    }

    @Test("A file cut off anywhere throws instead of crashing")
    func truncation() throws {
        let good = validFile(dataPayload: PBFFileBuilder.primitiveBlock(
            strings: ["", "a"],
            dense: PBFFileBuilder.denseNodes(ids: [1, 2], latitudes: [1, 2], longitudes: [1, 2])
        )).file
        try readAll(good)
        for length in 1..<good.count {
            // Cutting at a blob boundary leaves a valid, shorter file; every other cut must
            // fail with a PBFError, never another error type and never a crash.
            do {
                try readAll(good.prefix(length))
            } catch is PBFError {
            } catch {
                Issue.record("cut at \(length): unexpected error type \(error)")
            }
        }
        #expect(throws: PBFError.truncated) { try self.readAll(good.prefix(good.count - 1)) }
        #expect(throws: PBFError.truncated) { try self.readAll(good.prefix(2)) }
    }

    @Test("A BlobHeader larger than 64 KiB is rejected before allocation")
    func hugeBlobHeader() {
        var length = UInt32(100_000).bigEndian
        let data = Data(bytes: &length, count: 4) + Data(count: 100)
        do {
            try readAll(data)
            Issue.record("expected an error")
        } catch let error as PBFError {
            guard case .sizeLimitExceeded = error else {
                Issue.record("expected sizeLimitExceeded, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type \(error)")
        }
    }

    @Test("A declared blob size beyond the 32 MiB limit is rejected")
    func hugeBlob() {
        var builder = PBFFileBuilder()
        builder.appendRaw(type: "OSMHeader", blob: Data(), declaredDataSize: 100_000_000)
        #expect(throws: PBFError.self) { try self.readAll(builder.file) }
    }

    @Test("A declared raw_size that does not match the data fails to decompress")
    func wrongRawSize() {
        var builder = PBFFileBuilder()
        builder.appendBlob(type: "OSMHeader", payload: PBFFileBuilder.headerPayload(), declaredRawSize: 5)
        #expect(throws: PBFError.decompressionFailed) { try self.readAll(builder.file) }

        var larger = PBFFileBuilder()
        larger.appendBlob(type: "OSMHeader", payload: PBFFileBuilder.headerPayload(), declaredRawSize: 100_000)
        #expect(throws: PBFError.decompressionFailed) { try self.readAll(larger.file) }
    }

    @Test("A damaged zlib stream is detected")
    func damagedZlib() {
        var zlib = PBFFileBuilder.zlib(PBFFileBuilder.headerPayload())
        zlib[zlib.count - 1] ^= 0xff   // corrupt the Adler-32 checksum
        var blob = ProtobufWriter()
        blob.int(2, Int64(PBFFileBuilder.headerPayload().count))
        blob.bytes(3, zlib)
        var builder = PBFFileBuilder()
        builder.appendRaw(type: "OSMHeader", blob: blob.data)
        #expect(throws: PBFError.decompressionFailed) { try self.readAll(builder.file) }
    }

    @Test("Unsupported compression is reported by name")
    func unsupportedCompression() {
        var blob = ProtobufWriter()
        blob.bytes(4, Data([1, 2, 3]))   // lzma_data
        var builder = PBFFileBuilder()
        builder.appendRaw(type: "OSMHeader", blob: blob.data)
        #expect(throws: PBFError.unsupportedCompression("lzma")) { try self.readAll(builder.file) }
    }

    @Test("A file requiring an unknown feature is refused")
    func unsupportedRequiredFeature() {
        var builder = PBFFileBuilder()
        builder.appendBlob(
            type: "OSMHeader",
            payload: PBFFileBuilder.headerPayload(required: ["OsmSchema-V0.6", "SomeFutureFeature"])
        )
        #expect(throws: PBFError.unsupportedRequiredFeature("SomeFutureFeature")) { try self.readAll(builder.file) }
    }

    @Test("A tag that refers to a missing string is rejected")
    func invalidStringIndex() {
        let way = PBFFileBuilder.way(id: 1, nodeIDs: [1, 2], tags: [(key: 1, value: 99)])
        let builder = validFile(dataPayload: PBFFileBuilder.primitiveBlock(strings: ["", "highway"], ways: [way]))
        #expect(throws: PBFError.invalidStringIndex(99)) { try self.readAll(builder.file) }
    }

    @Test("Dense node arrays of different lengths are rejected")
    func inconsistentDenseNodes() {
        let dense = PBFFileBuilder.denseNodes(ids: [1, 2, 3], latitudes: [1, 2], longitudes: [1, 2, 3])
        let builder = validFile(dataPayload: PBFFileBuilder.primitiveBlock(strings: [""], dense: dense))
        #expect(throws: PBFError.self) { try self.readAll(builder.file) }
    }

    @Test("A relation with mismatched member arrays is rejected")
    func inconsistentRelation() {
        var relation = ProtobufWriter()
        relation.int(1, 5)
        relation.packedInt32(8, [0, 0])
        relation.packedSInt(9, [1])
        relation.packed(10, [0, 0])
        var group = ProtobufWriter()
        group.bytes(4, relation.data)
        var block = ProtobufWriter()
        block.bytes(1, PBFFileBuilder.stringTable([""]))
        block.bytes(2, group.data)
        let builder = validFile(dataPayload: block.data)
        #expect(throws: PBFError.self) { try self.readAll(builder.file) }
    }

    @Test("An unknown relation member type is rejected")
    func unknownMemberType() {
        let relation = PBFFileBuilder.relation(id: 1, members: [(id: 5, role: 0, type: 7)], tags: [])
        let builder = validFile(dataPayload: PBFFileBuilder.primitiveBlock(strings: [""], relations: [relation]))
        #expect(throws: PBFError.self) { try self.readAll(builder.file) }
    }

    @Test("A non-positive granularity is rejected")
    func badGranularity() {
        let builder = validFile(dataPayload: PBFFileBuilder.primitiveBlock(strings: [""], granularity: 0))
        #expect(throws: PBFError.self) { try self.readAll(builder.file) }
    }

    @Test("Random bytes never crash the reader")
    func randomBytes() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            let length = Int.random(in: 0..<200, using: &generator)
            let data = Data((0..<length).map { _ in UInt8.random(in: 0...255, using: &generator) })
            _ = try? readAll(data)
        }
    }
}
