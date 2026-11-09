import FeatureStore
import GeoCore

/// A feature of the source, identified across the cells it was cut into.
struct LevelKey: Hashable, Comparable {
    var classID: UInt8
    var type: UInt8
    var id: Int64

    static func < (a: LevelKey, b: LevelKey) -> Bool { (a.classID, a.type, a.id) < (b.classID, b.type, b.id) }
}

/// What does not change between the pieces of a feature.
struct LevelAttributes {
    var subclass: UInt8
    var name: String?
    var incomplete: Bool
}

/// One piece of a line in a source cell.
struct LevelLinePiece {
    var points: [PackedPoint]
    var continuesBefore: Bool
    var continuesAfter: Bool
}

/// One ring of an area piece in a source cell.
struct LevelRing {
    var cell: TileID
    var points: [PackedPoint]
    var artificialEdges: [Range<Int>]
}

/// The pieces read from the source, grouped by feature.
struct LevelCollection {
    var present: Set<TileID> = []
    var attributes: [LevelKey: LevelAttributes] = [:]
    var points: [(key: LevelKey, point: PackedPoint)] = []
    var lines: [LevelKey: [LevelLinePiece]] = [:]
    var rings: [LevelKey: [LevelRing]] = [:]

    mutating func add(_ feature: StoredFeature, in cell: TileID, of file: FeatureStoreFile) {
        let key = LevelKey(classID: feature.classID, type: feature.objectType.rawValue, id: feature.objectID)
        let incomplete = feature.flags.contains(.incomplete)
        if var known = attributes[key] {
            if incomplete && !known.incomplete { known.incomplete = true; attributes[key] = known }
        } else {
            attributes[key] = LevelAttributes(
                subclass: feature.subclass, name: feature.nameID.flatMap { file.string(at: $0) }, incomplete: incomplete)
        }
        switch feature.kind {
        case .point:
            if let point = feature.parts.first?.points.first { points.append((key, point)) }
        case .line:
            for part in feature.parts where part.points.count >= 2 {
                lines[key, default: []].append(
                    LevelLinePiece(
                        points: part.points, continuesBefore: feature.flags.contains(.continuesBefore),
                        continuesAfter: feature.flags.contains(.continuesAfter)))
            }
        case .area:
            for part in feature.parts where part.points.count >= 4 {
                rings[key, default: []].append(LevelRing(cell: cell, points: part.points, artificialEdges: part.artificialEdges))
            }
        }
    }
}
