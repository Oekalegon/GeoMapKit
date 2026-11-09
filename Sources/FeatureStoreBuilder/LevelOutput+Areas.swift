import FeatureStore
import GeoCore

extension LevelOutput {
    /// Dissolves the rings of every area feature, simplifies them, drops the small ones and cuts them into level cells.
    mutating func writeAreas(_ collected: LevelCollection, region: LevelRegion) throws {
        for key in collected.rings.keys.sorted() {
            guard let rings = collected.rings[key], var attributes = collected.attributes[key] else { continue }
            let dissolved = LevelDissolve.rings(of: rings, present: collected.present, region: region)
            report.openAreaChains += dissolved.open
            if dissolved.open > 0 { attributes.incomplete = true }
            var partsByCell: [TileID: [GeometryPart]] = [:]
            for ring in dissolved.rings {
                guard extent(ring) >= spec.minimumExtent else { report.droppedAsSmall += 1; continue }
                guard let simplified = GeometrySimplifier.simplify(ring: ring, tolerance: spec.tolerance) else {
                    report.droppedAsSmall += 1
                    continue
                }
                for (cell, piece) in CellSplitter.split(ring: simplified, zoom: spec.storageZoom) where inBlock(cell) {
                    partsByCell[cell, default: []].append(piece.part)
                }
            }
            for cell in partsByCell.keys.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
                guard let parts = FeatureEmitter.withoutCancellingSquares(partsByCell[cell] ?? [], in: cell), !parts.isEmpty else { continue }
                try add(key, attributes, kind: .area, parts: parts, in: cell)
            }
        }
    }
}
