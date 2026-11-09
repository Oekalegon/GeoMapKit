import FeatureStore
import Foundation
import GeoCore

/// Writes the features of a level block: points, joined lines and dissolved areas.
struct LevelOutput {
    var writer: FeatureStoreWriter
    let spec: LevelSpec
    let tile: TileID
    let block: LevelRegion
    var report: LevelReport

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
        var all = flags
        if attributes.incomplete { all.insert(.incomplete) }
        try writer.add(
            StoredFeature(
                classID: key.classID, subclass: attributes.subclass, kind: kind, objectType: StoredObjectType(rawValue: key.type) ?? .way,
                objectID: key.id, flags: all, offsetAlongLine: offset, nameID: nameID, parts: parts),
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

    mutating func writePoints(_ collected: LevelCollection) throws {
        for (key, point) in collected.points {
            guard let attributes = collected.attributes[key], let cell = CellRect.tile(owning: point, zoom: spec.storageZoom),
                inBlock(cell)
            else { continue }
            try add(key, attributes, kind: .point, parts: [GeometryPart(points: [point])], in: cell)
        }
    }
}
