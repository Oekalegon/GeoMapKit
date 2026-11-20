import Foundation
import GeoCore

/// A line as bytes: the latitude and the longitude of each point as 32-bit integers in 1e-7 degrees (about a centimetre), little-endian.
enum LineBlob {
    static func encode(_ coordinates: [Coordinate]) -> Data {
        var values: [Int32] = []
        values.reserveCapacity(coordinates.count * 2)
        for coordinate in coordinates {
            values.append(Int32(clamping: Int((coordinate.latitude * 1e7).rounded())).littleEndian)
            values.append(Int32(clamping: Int((coordinate.longitude * 1e7).rounded())).littleEndian)
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// The points of a line, or `nil` when the bytes are not whole points.
    static func decode(_ data: Data) -> [Coordinate]? {
        guard data.count % 8 == 0 else { return nil }
        let values = data.withUnsafeBytes { Array($0.bindMemory(to: Int32.self)) }.map { Int32(littleEndian: $0) }
        return stride(from: 0, to: values.count, by: 2).map { Coordinate(latitude: Double(values[$0]) / 1e7, longitude: Double(values[$0 + 1]) / 1e7) }
    }
}
