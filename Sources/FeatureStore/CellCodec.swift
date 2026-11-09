import Foundation

/// Encodes and decodes the content of one cell block.
///
/// Block layout: origin longitude and latitude (Int32 each, 1e-7 degrees), the byte
/// length of each of the three bands (UInt32 each), then the band bodies in order.
/// A band body is a class count, then per class (ascending): class ID, feature
/// count, byte length, and the feature records. Feature record: a flag byte (kind
/// in bits 0 to 1, object type in 2 to 3, piece flags in 4 to 6), zigzag object ID,
/// subclass, name ID plus one (0 for none), offset along the line, tag count and
/// tag string ID pairs, then the parts. A part is a vertex count, the vertices as
/// zigzag deltas (the first relative to the cell origin), a run count and the runs
/// as (start, length) pairs.
enum CellCodec {
    static let headerSize = 20
    static let maximumLongitude: Int64 = 1_800_000_000
    static let maximumLatitude: Int64 = 900_000_000

    // MARK: Encoding

    static func encode(
        originLongitude: Int32, originLatitude: Int32, bands: [ZoomBand: [StoredFeature]],
        stringCount: Int
    ) throws -> [UInt8] {
        var bodies: [[UInt8]] = []
        for band in ZoomBand.allCases {
            bodies.append(
                try encodeBand(
                    bands[band] ?? [], band: band, originLongitude: originLongitude, originLatitude: originLatitude,
                    stringCount: stringCount))
        }
        var writer = ByteWriter()
        writer.writeInt32(originLongitude)
        writer.writeInt32(originLatitude)
        for body in bodies {
            guard let length = UInt32(exactly: body.count) else { throw FeatureStoreError.invalidInput("band too large") }
            writer.writeUInt32(length)
        }
        for body in bodies { writer.writeBytes(body) }
        return writer.bytes
    }

    private static func encodeBand(
        _ features: [StoredFeature], band: ZoomBand, originLongitude: Int32, originLatitude: Int32,
        stringCount: Int
    ) throws -> [UInt8] {
        let ordered = features.sorted {
            ($0.classID, $0.objectType.rawValue, $0.objectID, $0.offsetAlongLine, $0.kind.rawValue)
                < ($1.classID, $1.objectType.rawValue, $1.objectID, $1.offsetAlongLine, $1.kind.rawValue)
        }
        var groups: [(classID: UInt8, features: ArraySlice<StoredFeature>)] = []
        var start = 0
        while start < ordered.count {
            var end = start
            while end < ordered.count && ordered[end].classID == ordered[start].classID { end += 1 }
            groups.append((ordered[start].classID, ordered[start..<end]))
            start = end
        }
        var writer = ByteWriter()
        writer.writeVarint(UInt64(groups.count))
        for group in groups {
            var body = ByteWriter()
            for feature in group.features {
                try encodeFeature(
                    // The tags of a feature are written as given in every band. The builder gives all tags in the detail band and none
                    // in the others, except the value tag of a `landUse` feature (rule table 19), so that a style can select by it. Every
                    // feature has a tag count, so the layout is the same and the format version does not change.
                    feature, includeTags: true, originLongitude: originLongitude,
                    originLatitude: originLatitude, stringCount: stringCount, into: &body)
            }
            writer.writeUInt8(group.classID)
            writer.writeVarint(UInt64(group.features.count))
            writer.writeVarint(UInt64(body.count))
            writer.writeBytes(body.bytes)
        }
        return writer.bytes
    }

    private static func encodeFeature(
        _ feature: StoredFeature, includeTags: Bool, originLongitude: Int32, originLatitude: Int32,
        stringCount: Int, into writer: inout ByteWriter
    ) throws {
        guard feature.flags.subtracting(.all).isEmpty else { throw FeatureStoreError.invalidInput("unknown feature flags") }
        writer.writeUInt8(
            feature.kind.rawValue | feature.objectType.rawValue << 2 | feature.flags.rawValue << 4)
        writer.writeZigzag(feature.objectID)
        writer.writeUInt8(feature.subclass)
        if let name = feature.nameID {
            guard Int(name) < stringCount else { throw FeatureStoreError.invalidInput("name string ID") }
            writer.writeVarint(UInt64(name) + 1)
        } else {
            writer.writeVarint(0)
        }
        writer.writeVarint(UInt64(feature.offsetAlongLine))
        let tags = includeTags ? feature.tags : []
        writer.writeVarint(UInt64(tags.count))
        for tag in tags {
            guard Int(tag.key) < stringCount, Int(tag.value) < stringCount else {
                throw FeatureStoreError.invalidInput("tag string ID")
            }
            writer.writeVarint(UInt64(tag.key))
            writer.writeVarint(UInt64(tag.value))
        }
        writer.writeVarint(UInt64(feature.parts.count))
        for part in feature.parts {
            writer.writeVarint(UInt64(part.points.count))
            var longitude = Int64(originLongitude), latitude = Int64(originLatitude)
            for point in part.points {
                guard abs(Int64(point.longitude)) <= maximumLongitude, abs(Int64(point.latitude)) <= maximumLatitude else {
                    throw FeatureStoreError.invalidInput("coordinate out of range")
                }
                writer.writeZigzag(Int64(point.longitude) - longitude)
                writer.writeZigzag(Int64(point.latitude) - latitude)
                longitude = Int64(point.longitude)
                latitude = Int64(point.latitude)
            }
            let edgeCount = max(part.points.count - 1, 0)
            writer.writeVarint(UInt64(part.artificialEdges.count))
            for run in part.artificialEdges {
                guard run.lowerBound >= 0, run.upperBound <= edgeCount else {
                    throw FeatureStoreError.invalidInput("artificial edge run out of range")
                }
                writer.writeVarint(UInt64(run.lowerBound))
                writer.writeVarint(UInt64(run.count))
            }
        }
    }

    // MARK: Decoding

    struct BlockLayout {
        let originLongitude: Int32
        let originLatitude: Int32
        let bands: [Range<Int>]
    }

    static func layout(of data: Data, block: Range<Int>) throws -> BlockLayout {
        var cursor = ByteCursor(data, range: block)
        let longitude = try cursor.readInt32()
        let latitude = try cursor.readInt32()
        var lengths: [Int] = []
        for _ in ZoomBand.allCases { lengths.append(Int(try cursor.readUInt32())) }
        var bands: [Range<Int>] = []
        for length in lengths { bands.append(try cursor.skip(length)) }
        guard cursor.isAtEnd else { throw FeatureStoreError.corrupt("cell block has trailing bytes") }
        return BlockLayout(originLongitude: longitude, originLatitude: latitude, bands: bands)
    }

    /// The number of features per class in a band, read from the class headers without decoding any feature.
    static func featureCounts(data: Data, layout: BlockLayout, band: ZoomBand) throws -> [UInt8: Int] {
        let range = layout.bands[Int(band.rawValue)]
        guard !range.isEmpty else { return [:] }
        var cursor = ByteCursor(data, range: range)
        let classCount = try cursor.readCount(limit: 256)
        var counts: [UInt8: Int] = [:]
        for _ in 0..<classCount {
            let classID = try cursor.readUInt8()
            counts[classID] = try cursor.readCount(limit: cursor.remaining)
            _ = try cursor.skip(try cursor.readCount(limit: cursor.remaining))
        }
        return counts
    }

    /// Decodes the features of one band, optionally only those of the given classes.
    static func decodeBand(
        data: Data, layout: BlockLayout, band: ZoomBand, classes: Set<UInt8>?, stringCount: Int
    ) throws -> [StoredFeature] {
        let range = layout.bands[Int(band.rawValue)]
        guard !range.isEmpty else { return [] }
        var cursor = ByteCursor(data, range: range)
        let classCount = try cursor.readCount(limit: 256)
        var result: [StoredFeature] = []
        var previousClass = -1
        for _ in 0..<classCount {
            let classID = try cursor.readUInt8()
            guard Int(classID) > previousClass else { throw FeatureStoreError.corrupt("classes not ascending") }
            previousClass = Int(classID)
            let featureCount = try cursor.readCount(limit: cursor.remaining)
            let byteLength = try cursor.readCount(limit: cursor.remaining)
            let bodyRange = try cursor.skip(byteLength)
            if let classes, !classes.contains(classID) { continue }
            var body = ByteCursor(data, range: bodyRange)
            result.reserveCapacity(result.count + featureCount)
            for _ in 0..<featureCount {
                result.append(try decodeFeature(&body, classID: classID, layout: layout, stringCount: stringCount))
            }
            guard body.isAtEnd else { throw FeatureStoreError.corrupt("class body has trailing bytes") }
        }
        guard cursor.isAtEnd else { throw FeatureStoreError.corrupt("band has trailing bytes") }
        return result
    }

    private static func decodeFeature(
        _ cursor: inout ByteCursor, classID: UInt8, layout: BlockLayout, stringCount: Int
    ) throws -> StoredFeature {
        let first = try cursor.readUInt8()
        guard let kind = FeatureKind(rawValue: first & 3), let type = StoredObjectType(rawValue: (first >> 2) & 3),
            first >> 7 == 0
        else { throw FeatureStoreError.corrupt("feature header byte") }
        let flags = FeatureFlags(rawValue: (first >> 4) & 7)
        let objectID = try cursor.readZigzag()
        let subclass = try cursor.readUInt8()
        let nameValue = try cursor.readVarint()
        var nameID: UInt32?
        if nameValue > 0 {
            guard nameValue <= UInt64(stringCount) else { throw FeatureStoreError.corrupt("name string ID") }
            nameID = UInt32(nameValue - 1)
        }
        guard let offset = UInt32(exactly: try cursor.readVarint()) else { throw FeatureStoreError.corrupt("offset") }
        let tagCount = try cursor.readCount(limit: cursor.remaining / 2)
        var tags: [StoredTag] = []
        tags.reserveCapacity(tagCount)
        for _ in 0..<tagCount {
            let key = try cursor.readCount(limit: stringCount - 1)
            let value = try cursor.readCount(limit: stringCount - 1)
            tags.append(StoredTag(key: UInt32(key), value: UInt32(value)))
        }
        let partCount = try cursor.readCount(limit: cursor.remaining)
        var parts: [GeometryPart] = []
        parts.reserveCapacity(partCount)
        for _ in 0..<partCount {
            let pointCount = try cursor.readCount(limit: cursor.remaining / 2)
            var points: [PackedPoint] = []
            points.reserveCapacity(pointCount)
            var longitude = Int64(layout.originLongitude), latitude = Int64(layout.originLatitude)
            for _ in 0..<pointCount {
                let (lon, lonOverflow) = longitude.addingReportingOverflow(try cursor.readZigzag())
                let (lat, latOverflow) = latitude.addingReportingOverflow(try cursor.readZigzag())
                guard !lonOverflow, !latOverflow, abs(lon) <= maximumLongitude, abs(lat) <= maximumLatitude else {
                    throw FeatureStoreError.corrupt("coordinate out of range")
                }
                longitude = lon
                latitude = lat
                points.append(PackedPoint(longitude: Int32(lon), latitude: Int32(lat)))
            }
            let edgeCount = max(pointCount - 1, 0)
            let runCount = try cursor.readCount(limit: cursor.remaining / 2)
            var runs: [Range<Int>] = []
            for _ in 0..<runCount {
                let start = try cursor.readCount(limit: edgeCount)
                let length = try cursor.readCount(limit: edgeCount - start)
                runs.append(start..<(start + length))
            }
            parts.append(GeometryPart(points: points, artificialEdges: runs))
        }
        return StoredFeature(
            classID: classID, subclass: subclass, kind: kind, objectType: type, objectID: objectID, flags: flags,
            offsetAlongLine: offset, nameID: nameID, tags: tags, parts: parts)
    }
}
