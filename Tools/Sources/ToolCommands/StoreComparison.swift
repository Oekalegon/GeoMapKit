import FeatureStore
import Foundation
import GeoCore
import ToolSupport

/// The difference between two stores in the cells that both have.
///
/// A store is a `.gmk` file or a `manifest.json` of blocks. Names and tags are compared as text, so two stores with different
/// string tables compare equal when they say the same.
public struct StoreComparison: Sendable {
    /// One difference in one cell and band.
    public struct Difference: Sendable, Equatable {
        public let cell: TileID
        public let band: ZoomBand
        /// A description of the feature that one store has and the other does not.
        public let feature: String
        /// Which store has the feature: `first` or `second`.
        public let onlyIn: String
    }

    /// The number of cells that both stores have.
    public let cellsCompared: Int
    /// The number of those cells that are the same in every band.
    public let cellsIdentical: Int
    /// The number of cells of the first store that the second does not have.
    public let cellsOnlyInFirst: Int
    /// The number of cells that were left out because they lie near the edge of the first store (see `inner`).
    public let cellsSkippedNearEdge: Int
    /// The differences, at most the first `limit`.
    public let differences: [Difference]
    /// The total number of differing features.
    public let differenceCount: Int
}

extension ToolRunner {
    /// Compares two stores cell by cell.
    ///
    /// - Parameters:
    ///   - first: A `.gmk` file or a manifest.
    ///   - second: A `.gmk` file or a manifest.
    ///   - limit: How many differences to keep in the report.
    ///   - inner: Cells within this many cells of the edge of the first store are left out. A store made from one cut is poor
    ///     at its own edge (objects are cut off, the sea is not closed), so against such a reference the edge would count as
    ///     differences that the other store does not have. 0 compares every cell.
    /// - Returns: The comparison, over the cells that both stores hold.
    /// - Throws: ``ToolError`` if a store cannot be opened, and the errors of the readers.
    public static func compareStores(_ first: URL, _ second: URL, limit: Int = 20, inner: Int = 0) throws -> StoreComparison {
        let a = try openStore(first), b = try openStore(second)
        guard a.source.storageZoom == b.source.storageZoom else { throw ToolError("The stores have different cell zooms") }
        var compared = 0, identical = 0, onlyFirst = 0, count = 0, skipped = 0
        var differences: [StoreComparison.Difference] = []
        let firstCells = try a.cells()
        let columns = firstCells.map(\.x), rows = firstCells.map(\.y)
        let (west, east, north, south) = (columns.min() ?? 0, columns.max() ?? 0, rows.min() ?? 0, rows.max() ?? 0)
        for cell in firstCells {
            if inner > 0, cell.x < west + inner || cell.x > east - inner || cell.y < north + inner || cell.y > south - inner {
                skipped += 1
                continue
            }
            guard let fileA = try a.source.file(containing: cell) else { continue }
            guard let fileB = try b.source.file(containing: cell) else { onlyFirst += 1; continue }
            compared += 1
            var same = true
            for band in ZoomBand.allCases where a.source.bands.contains(band) && b.source.bands.contains(band) {
                let left = Set(try fileA.features(in: cell, band: band).map { Plain($0, fileA) })
                let right = Set(try fileB.features(in: cell, band: band).map { Plain($0, fileB) })
                for (features, owner) in [(left.subtracting(right), "first"), (right.subtracting(left), "second")] {
                    for feature in features.sorted(by: { ($0.classID, $0.id) < ($1.classID, $1.id) }) {
                        same = false
                        count += 1
                        if differences.count < limit {
                            differences.append(StoreComparison.Difference(cell: cell, band: band, feature: feature.description, onlyIn: owner))
                        }
                    }
                }
            }
            if same { identical += 1 }
        }
        return StoreComparison(
            cellsCompared: compared, cellsIdentical: identical, cellsOnlyInFirst: onlyFirst, cellsSkippedNearEdge: skipped,
            differences: differences, differenceCount: count)
    }

    private struct OpenStore {
        let source: any CellSource
        let cells: () throws -> [TileID]
    }

    private static func openStore(_ url: URL) throws -> OpenStore {
        do {
            if url.pathExtension.lowercased() == "json" {
                let set = try StoreSet(manifestURL: url)
                return OpenStore(source: set, cells: { try set.cells() })
            }
            let file = try FeatureStoreFile(contentsOf: url)
            return OpenStore(source: file, cells: { try file.cells() })
        } catch {
            throw ToolError("Cannot open \(url.path): \(error)")
        }
    }

    /// A feature without the numbers that belong to its file: its name and tags as text.
    private struct Plain: Hashable, CustomStringConvertible {
        var classID: UInt8, subclass: UInt8, kind: FeatureKind, type: StoredObjectType, id: Int64, flags: FeatureFlags, offset: UInt32
        var name: String?, tags: [[String]], parts: [GeometryPart]

        init(_ feature: StoredFeature, _ file: FeatureStoreFile) {
            classID = feature.classID
            subclass = feature.subclass
            kind = feature.kind
            type = feature.objectType
            id = feature.objectID
            flags = feature.flags
            offset = feature.offsetAlongLine
            name = feature.nameID.flatMap { file.string(at: $0) }
            tags = feature.tags.map { [file.string(at: $0.key) ?? "", file.string(at: $0.value) ?? ""] }
            parts = feature.parts
        }

        var description: String {
            let className = FeatureClass(rawValue: classID).map { "\($0)" } ?? "class \(classID)"
            let points = parts.reduce(0) { $0 + $1.points.count }
            return "\(className) \(type) \(id)\(name.map { " \"\($0)\"" } ?? ""), \(points) points"
        }
    }
}
