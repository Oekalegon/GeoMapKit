import FeatureStore
import Foundation
import GeoCore
import OSMPBF

/// Builds a feature store file from an `OSMExtract`.
///
/// The builder classifies every object, simplifies it per band, clips it to cells, assembles
/// multipolygons and writes the result with `FeatureStoreWriter`. Nothing is dropped: all
/// tagged nodes, all ways and all relations are stored with all their tags, except in the
/// ``BuildProfile/watch`` copy. Only cells that lie fully inside the extract's bounding box are
/// written, because the extract is incomplete near its edge; pieces outside them are counted.
///
/// Ways join multipolygons by node ID; a multipolygon that cannot be assembled completely is stored
/// as outlines only (see `architecture.md`). Untagged ways that are members of a multipolygon are
/// not stored separately, since their geometry is part of the area and their IDs are in the relation.
///
/// The builder is meant for the phone or Mac. It holds the whole result in memory.
public struct FeatureStoreBuilder: Sendable {
    /// The OSM attribution written into every file.
    public static let attribution = "© OpenStreetMap contributors, ODbL"

    /// Which copy to build.
    public let profile: BuildProfile
    /// The date of the source data, recorded in the file header, or `nil` if unknown.
    public let sourceDate: Date?

    let classifier = FeatureClassifier()
    static let zoom = 13
    /// The zoom of the cells the builder writes.
    public static let storageZoom = zoom

    /// Creates a builder.
    ///
    /// - Parameters:
    ///   - profile: The copy to build.
    ///   - sourceDate: The date of the source data.
    public init(profile: BuildProfile = .full, sourceDate: Date? = nil) {
        self.profile = profile
        self.sourceDate = sourceDate
    }

    /// Builds the file.
    ///
    /// - Parameter extract: The cut area.
    /// - Returns: The file data and a report.
    /// - Throws: `CancellationError` if the task is cancelled, or `FeatureStoreError` if a value does not fit the format.
    public func build(from extract: OSMExtract) throws -> BuildResult {
        try build(from: extract, writing: extract.boundingBox)
    }

    /// Builds the file for the cells of one part of the extract.
    ///
    /// For a big area that is stored as blocks: each block is cut with a margin, so that the objects near its edge are whole, and
    /// built for its own cells only. The cells are the ones that lie fully inside `area` and inside the extract's box; the rest
    /// of the extract is used (for the sea, for roads, for the joining of areas) but nothing of it is written.
    ///
    /// - Parameters:
    ///   - extract: The cut area, larger than `area` by a margin.
    ///   - area: The part to write. Its edges should be cell borders (see ``cellAlignedBox(covering:)``).
    /// - Returns: The file data, with the cells inside `area`, and a report.
    /// - Throws: `CancellationError` if the task is cancelled, or `FeatureStoreError` if a value does not fit the format.
    public func build(from extract: OSMExtract, writing area: BoundingBox) throws -> BuildResult {
        let inside = extract.boundingBox
        let part = BoundingBox(
            south: max(area.south, inside.south), west: max(area.west, inside.west), north: min(area.north, inside.north),
            east: min(area.east, inside.east))
        let range = part.south <= part.north && part.west <= part.east ? Self.writtenCells(in: part) : nil
        let writer = FeatureStoreWriter(
            storageZoom: Self.zoom, boundingBox: range.map(Self.boundingBox(of:)) ?? part,
            attribution: Self.attribution, sourceDate: sourceDate, classifierVersion: FeatureClassifier.version)
        var emitter = FeatureEmitter(writer: writer, profile: profile, columns: range?.columns, rows: range?.rows)
        if let range { emitter.report.cellsInArea = range.columns.count * range.rows.count }

        var shore = ShoreContext(extract: extract, classifier: classifier)
        let sea = try range.flatMap { try prepareSea(of: extract, columns: $0.columns, rows: $0.rows, into: &emitter) }
        shore.sea = sea.map { SeaLookup(rings: $0.whole.rings) }

        // The index of the border relations, built by whichever step needs it first and shared with the other.
        var borders: BorderNames?
        let suppressed = try storeRelations(of: extract, borders: &borders, shore: &shore, into: &emitter)
        try storeWays(of: extract, suppressed: suppressed, borders: &borders, shore: &shore, into: &emitter)
        try storeNodes(of: extract, into: &emitter)
        if let range, let sea { try storeSea(sea, columns: range.columns, rows: range.rows, into: &emitter) }
        return BuildResult(data: try emitter.writer.data(), report: emitter.report)
    }

    // MARK: Cells

    /// The columns and rows of the cells that lie fully inside a box, or `nil` if there are none.
    static func writtenCells(in box: BoundingBox) -> (columns: ClosedRange<Int>, rows: ClosedRange<Int>)? {
        let n = 1 << zoom
        func e7(_ degrees: Double) -> Int32 { Int32(max(-1_800_000_000, min(1_800_000_000, (degrees * 1e7).rounded()))) }
        let west = e7(box.west), east = e7(box.east), south = e7(box.south), north = e7(box.north)
        let firstColumn = max(0, Int(((box.west + 180) / 360 * Double(n)).rounded(.down)) - 1)
        let lastColumn = min(n - 1, Int(((box.east + 180) / 360 * Double(n)).rounded(.down)) + 1)
        let columns = (firstColumn...max(firstColumn, lastColumn)).filter {
            CellRect.longitude(column: $0, zoom: zoom) >= west && CellRect.longitude(column: $0 + 1, zoom: zoom) <= east
        }
        func row(_ latitude: Double) -> Int {
            let y = Mercator.y(latitude: latitude * 1e7)
            return max(0, min(n - 1, Int(((1 - y / .pi) / 2 * Double(n)).rounded(.down))))
        }
        let firstRow = max(0, row(box.north) - 1), lastRow = min(n - 1, row(box.south) + 1)
        let rows = (firstRow...max(firstRow, lastRow)).filter {
            CellRect.latitude(row: $0, zoom: zoom) <= north && CellRect.latitude(row: $0 + 1, zoom: zoom) >= south
        }
        guard let firstC = columns.first, let lastC = columns.last, let firstR = rows.first, let lastR = rows.last else { return nil }
        return (firstC...lastC, firstR...lastR)
    }

    private static func boundingBox(of range: (columns: ClosedRange<Int>, rows: ClosedRange<Int>)) -> BoundingBox {
        BoundingBox(
            south: Double(CellRect.latitude(row: range.rows.upperBound + 1, zoom: zoom)) / 1e7,
            west: Double(CellRect.longitude(column: range.columns.lowerBound, zoom: zoom)) / 1e7,
            north: Double(CellRect.latitude(row: range.rows.lowerBound, zoom: zoom)) / 1e7,
            east: Double(CellRect.longitude(column: range.columns.upperBound + 1, zoom: zoom)) / 1e7)
    }

    // MARK: Helpers

    static func packed(_ coordinate: Coordinate) -> PackedPoint {
        PackedPoint(
            longitude: Int32((coordinate.longitude * 1e7).rounded()), latitude: Int32((coordinate.latitude * 1e7).rounded()))
    }

    /// The points of a way, split into runs at nodes that are missing from the extract.
    static func runs(ofWayAt position: Int, in extract: OSMExtract) -> (runs: [[PackedPoint]], gaps: Int) {
        var runs: [[PackedPoint]] = []
        var current: [PackedPoint] = []
        var gaps = 0
        for nodeID in extract.ways.nodeIDs(at: position) {
            if let index = extract.nodes.index(ofID: nodeID) {
                current.append(packed(extract.nodes.coordinate(at: index)))
            } else {
                gaps += 1
                if current.count >= 2 { runs.append(current) }
                current = []
            }
        }
        if current.count >= 2 { runs.append(current) }
        return (runs, gaps)
    }
}
