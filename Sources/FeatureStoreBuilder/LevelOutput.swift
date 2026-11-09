import FeatureStore
import Foundation
import GeoCore

/// A feature that is a water area.
struct LevelWaterKey: Hashable {
    var type: UInt8
    var id: Int64
}

/// Writes the features of a level block: points, joined lines and dissolved areas.
struct LevelOutput {
    var writer: FeatureStoreWriter
    let spec: LevelSpec
    let tile: TileID
    let block: LevelRegion
    var report: LevelReport
    /// The water areas (object type and ID) that were left out as thin or small: their outlines (`waterEdge`) go with them.
    var droppedWater: Set<LevelWaterKey> = []
    /// The rings of the water areas that were kept, one list of rings (even-odd) for each feature: a river name that does not lie in one
    /// of them is written as the river line, because its area is not drawn at this level.
    var keptWater: [(box: (minX: Int32, maxX: Int32, minY: Int32, maxY: Int32), rings: [[PackedPoint]])] = []

    init(writer: FeatureStoreWriter, spec: LevelSpec, tile: TileID, block: LevelRegion, report: LevelReport) {
        self.writer = writer
        self.spec = spec
        self.tile = tile
        self.block = block
        self.report = report
    }

    /// Whether a cell of the level lies in the block.
    func inBlock(_ cell: TileID) -> Bool { block.contains(x: cell.x, y: cell.y) }

    /// A feature in one cell of the level.
    mutating func add(
        _ key: LevelKey, _ attributes: LevelAttributes, kind: FeatureKind, flags: FeatureFlags = [], offset: UInt32 = 0,
        parts: [GeometryPart], in cell: TileID
    ) throws {
        let nameID = attributes.name.map { writer.intern($0) }
        let tags = attributes.population.map { [StoredTag(key: writer.intern("population"), value: writer.intern($0))] } ?? []
        var all = flags
        if attributes.incomplete { all.insert(.incomplete) }
        try writer.add(
            StoredFeature(
                classID: key.classID, subclass: attributes.subclass, kind: kind, objectType: StoredObjectType(rawValue: key.type) ?? .way,
                objectID: key.id, flags: all, offsetAlongLine: offset, nameID: nameID, tags: tags, parts: parts),
            band: .overview, cell: cell)
        report.featuresWritten += 1
        report.verticesWritten += parts.reduce(0) { $0 + $1.points.count }
    }

    /// Extent of a set of points in projected radians (the diagonal of the bounding box).
    func extent(_ points: [PackedPoint]) -> Double {
        guard let first = points.first else { return 0 }
        var minX = Double(first.longitude), maxX = minX
        var minY = Mercator.y(latitude: Double(first.latitude)), maxY = minY
        for point in points {
            let x = Double(point.longitude), y = Mercator.y(latitude: Double(point.latitude))
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
        return hypot((maxX - minX) * .pi / 180 / 1e7, maxY - minY)
    }

    /// The mean width and the area of the dissolved rings, in projected radians (the Mercator projection is conformal, so the ratio
    /// needs no correction for the latitude). Every ring is counted with its absolute area, holes included, which is a bit more
    /// than the water: an island in a lake counts for the lake.
    func widthAndArea(of rings: [[PackedPoint]]) -> (width: Double, area: Double) {
        var area = 0.0, perimeter = 0.0
        for ring in rings where ring.count >= 4 {
            var twice = 0.0
            for index in 0..<(ring.count - 1) {
                let ax = Double(ring[index].longitude) * .pi / 180 / 1e7, ay = Mercator.y(latitude: Double(ring[index].latitude))
                let bx = Double(ring[index + 1].longitude) * .pi / 180 / 1e7, by = Mercator.y(latitude: Double(ring[index + 1].latitude))
                twice += ax * by - bx * ay
                perimeter += hypot(bx - ax, by - ay)
            }
            area += abs(twice) / 2
        }
        return (perimeter > 0 ? 2 * area / perimeter : 0, area)
    }

    /// Whether a point lies in the water of a kept water area (inside an odd number of the rings of one feature).
    func isInKeptWater(_ point: PackedPoint) -> Bool {
        let x = Double(point.longitude), y = Double(point.latitude)
        for (box, rings) in keptWater {
            guard point.longitude >= box.minX, point.longitude <= box.maxX, point.latitude >= box.minY, point.latitude <= box.maxY else { continue }
            var inside = false
            for ring in rings where ring.count >= 4 {
                var j = ring.count - 1
                for i in 0..<ring.count {
                    let a = ring[i], b = ring[j]
                    if (Double(a.latitude) > y) != (Double(b.latitude) > y),
                        x < (Double(b.longitude) - Double(a.longitude)) * (y - Double(a.latitude)) / (Double(b.latitude) - Double(a.latitude)) + Double(a.longitude)
                    {
                        inside.toggle()
                    }
                    j = i
                }
            }
            if inside { return true }
        }
        return false
    }

    /// The bounding box of rings, for the quick test in ``isInKeptWater(_:)``.
    static func box(of rings: [[PackedPoint]]) -> (minX: Int32, maxX: Int32, minY: Int32, maxY: Int32)? {
        let points = rings.joined()
        guard let first = points.first else { return nil }
        var box = (minX: first.longitude, maxX: first.longitude, minY: first.latitude, maxY: first.latitude)
        for point in points {
            box.minX = min(box.minX, point.longitude); box.maxX = max(box.maxX, point.longitude)
            box.minY = min(box.minY, point.latitude); box.maxY = max(box.maxY, point.latitude)
        }
        return box
    }

    mutating func writePoints(_ collected: LevelCollection) throws {
        for (key, point) in collected.points {
            guard let attributes = collected.attributes[key], let cell = CellRect.tile(owning: point, zoom: spec.storageZoom),
                inBlock(cell)
            else { continue }
            try add(key, attributes, kind: .point, parts: [GeometryPart(points: [point])], in: cell)
        }
    }
}
