import Foundation
import Testing
import PBFTestSupport
@testable import OSMPBF

@Suite("ProtobufReader")
struct ProtobufReaderTests {
    @Test("Varints decode, including the largest value")
    func varints() throws {
        var writer = ProtobufWriter()
        for value: UInt64 in [0, 1, 127, 128, 300, 16_384, UInt64(UInt32.max), UInt64.max] { writer.varint(value) }
        var reader = ProtobufReader(writer.data)
        for expected: UInt64 in [0, 1, 127, 128, 300, 16_384, UInt64(UInt32.max), UInt64.max] {
            #expect(try reader.readVarint() == expected)
        }
        #expect(reader.isAtEnd)
    }

    @Test("A varint longer than ten bytes or overflowing 64 bits throws")
    func overlongVarint() {
        var reader = ProtobufReader(Data(repeating: 0xff, count: 11))
        #expect(throws: PBFError.invalidVarint) { try reader.readVarint() }

        var overflow = ProtobufReader(Data([0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x02]))
        #expect(throws: PBFError.invalidVarint) { try overflow.readVarint() }
    }

    @Test("A truncated varint throws")
    func truncatedVarint() {
        var reader = ProtobufReader(Data([0x80]))
        #expect(throws: PBFError.truncated) { try reader.readVarint() }
    }

    @Test("Zigzag decoding of signed values")
    func zigZag() {
        for value: Int64 in [0, -1, 1, -2, 2, 1_000_000, -1_000_000, Int64.max, Int64.min] {
            #expect(ProtobufReader.zigZagDecode(ProtobufWriter.zigZag(value)) == value)
        }
    }

    @Test("A length larger than the remaining bytes throws instead of reading out of bounds")
    func lengthBeyondData() {
        var writer = ProtobufWriter()
        writer.varint(1_000_000)
        writer.varint(1)
        var reader = ProtobufReader(writer.data)
        #expect(throws: PBFError.truncated) { try reader.readBytes() }
    }

    @Test("Field keys, strings and skipping unknown fields")
    func fieldsAndSkipping() throws {
        var writer = ProtobufWriter()
        writer.uint(5, 99)           // unknown varint
        writer.string(6, "skipped")  // unknown bytes
        writer.string(1, "héllo")
        var reader = ProtobufReader(writer.data)
        var found: String?
        while let (number, wire) = try reader.readFieldKey() {
            if number == 1 { found = try reader.readString() } else { try reader.skip(wire) }
        }
        #expect(found == "héllo")
    }

    @Test("Groups are rejected and field number zero is invalid")
    func invalidKeys() {
        var group = ProtobufReader(Data([0x0b]))   // field 1, wire type 3 (start group)
        #expect(throws: PBFError.self) {
            if let (_, wire) = try group.readFieldKey() { try group.skip(wire) }
        }
        var zero = ProtobufReader(Data([0x00]))    // field 0
        #expect(throws: PBFError.self) { try zero.readFieldKey() }
    }

    @Test("Adler-32 matches the known value for a short string")
    func adler() {
        #expect(ZlibInflater.adler32(Array("Wikipedia".utf8)) == 0x11E6_0398)
    }
}
