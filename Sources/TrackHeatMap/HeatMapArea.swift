import FeatureStore
import Foundation
import GeoCore
import MapRender
import TrackMatching
import TrackOverlays
import TrackStorage

/// The ways of an area of a map, joined to the store: what makes a heat map or a time-lapse of the counts in that area.
///
/// The ways come from the detail band of the map (a ``LineNetwork`` of the box), so the lines are as detailed as the map and the counts
/// of the store, which are along those ways, fall on them. Making the area reads the cells of the box once; after that an overlay is
/// made from the store alone. Lines off the paths (the traces of the store whose own box meets the area) are drawn too, each with one
/// count for its whole length, on the same scale. The area is not for a country: the overlay keeps every run in memory (see ``HeatMapOverlay``).
public final class HeatMapArea: Sendable {
    /// The store.
    public let store: TrackStore
    /// The geometry of the ways.
    public let ways: HeatMapWays
    /// The OSM ids of the ways of the area.
    let wayIDs: [Int64]
    /// The box that was asked for.
    public let box: BoundingBox

    /// Reads the ways of a box of the map.
    ///
    /// Runs off the main actor: reading the cells and joining the edges takes seconds for a city.
    ///
    /// - Parameters:
    ///   - store: The store with the counts.
    ///   - source: The map that the activities were matched on (the same ways, with the same ids and distances).
    ///   - box: The area.
    ///   - classes: The feature classes that count as lines; the ones the activities were matched on.
    /// - Throws: ``LineNetworkError`` for a box that is not valid or too large; the errors of the map.
    @concurrent
    public static func make(
        store: TrackStore, source: any CellSource, box: BoundingBox, classes: Set<UInt8> = LineNetwork.travelClasses
    ) async throws -> HeatMapArea {
        let network = try LineNetwork(source: source, box: box, classes: classes)
        return HeatMapArea(store: store, ways: HeatMapWays(network: network), box: box)
    }

    init(store: TrackStore, ways: HeatMapWays, box: BoundingBox) {
        self.store = store
        self.ways = ways
        wayIDs = ways.wayIDs
        self.box = box
    }

    /// The heat map of some categories and months, added together.
    ///
    /// - Parameters:
    ///   - categories: The categories to count, or `nil` for all.
    ///   - months: The months to count, or `nil` for all.
    ///   - measure: What to count.
    ///   - includeTraces: Whether the lines off the paths (the traces of the store) in the area are drawn too, on the same scale.
    ///   - scale: How a count looks; the same scale for two frames means the same colour for the same count.
    /// - Throws: ``TrackStoreError``.
    public func frame(
        categories: Set<String>? = nil, months: ClosedRange<TrackMonth>? = nil, measure: HeatMapMeasure = .activities,
        includeTraces: Bool = true, scale: HeatMapScale = .standard
    ) async throws -> HeatMapFrame {
        let counts = try await store.counts(ways: wayIDs, categories: categories, months: months)
        let buckets = counts.map { HeatMapBucket(wayID: $0.wayID, bucket: $0.bucket, count: measure == .passes ? $0.passes : $0.activities) }
        let stored = try await store.activityMonths(categories: categories)
        let lines: [HeatMapTraceLine] =
            includeTraces
            ? try await store.traces(in: box, categories: categories, months: months)
                .map { HeatMapTraceLine(coordinates: $0.coordinates, count: measure == .passes ? $0.passes : $0.activities) }
            : []
        return Self.frame(
            buckets: buckets, traces: lines, ways: ways, wayCount: wayIDs.count, months: months ?? stored,
            filtered: categories != nil || months != nil, scale: scale)
    }

    /// A time-lapse of the counts of some categories, month by month.
    ///
    /// - Parameters:
    ///   - categories: The categories to count, or `nil` for all.
    ///   - measure: What to count.
    ///   - includeTraces: Whether the lines off the paths in the area are drawn too (see ``frame(categories:months:measure:includeTraces:scale:)``).
    ///   - scale: How a count looks; it is the same for every frame, so the colours of two months can be compared.
    /// - Returns: The time-lapse, or `nil` when the store has no activity in those categories.
    /// - Throws: ``TrackStoreError``.
    public func timeLapse(
        categories: Set<String>? = nil, measure: HeatMapMeasure = .activities, includeTraces: Bool = true, scale: HeatMapScale = .standard
    ) async throws -> HeatMapTimeLapse? {
        guard let range = try await store.activityMonths(categories: categories) else { return nil }
        let counts = try await store.monthlyCounts(ways: wayIDs, categories: categories, months: range)
        var traces: [StoredTrace] = []
        var traceCounts: [MonthlyTraceCount] = []
        if includeTraces {
            traces = try await store.traces(in: box, categories: categories, months: range)
            traceCounts = try await store.monthlyTraceCounts(in: box, categories: categories, months: range)
        }
        return HeatMapTimeLapse(range: range, counts: counts, traces: traces, traceCounts: traceCounts, measure: measure, ways: ways, scale: scale)
    }

    /// The box of what a viewport shows, for the area of a heat map: the corners of the view (with its rotation), widened by a margin.
    ///
    /// - Parameters:
    ///   - viewport: The view.
    ///   - margin: The share of the width and the height that is added on every side, so that a small pan stays inside the area.
    /// - Returns: The box, in latitudes within the Web Mercator limits.
    public static func box(of viewport: MapViewport, margin: Double = 0.1) -> BoundingBox {
        let extra = max(margin, 0)
        let width = viewport.width * (1 + 2 * extra), height = viewport.height * (1 + 2 * extra)
        let wide = MapViewport(center: viewport.center, zoom: viewport.zoom, width: width, height: height, bearing: viewport.bearing)
        let corners = [ScreenPoint(x: 0, y: 0), ScreenPoint(x: width, y: 0), ScreenPoint(x: 0, y: height), ScreenPoint(x: width, y: height)]
            .map { wide.coordinate(at: $0) }
        return BoundingBox(
            south: max(corners.map(\.latitude).min() ?? 0, -85), west: max(corners.map(\.longitude).min() ?? 0, -180),
            north: min(corners.map(\.latitude).max() ?? 0, 85), east: min(corners.map(\.longitude).max() ?? 0, 180))
    }

    static func frame(
        buckets: [HeatMapBucket], traces: [HeatMapTraceLine] = [], ways: HeatMapWays, wayCount: Int, months: ClosedRange<TrackMonth>?, filtered: Bool,
        scale: HeatMapScale
    ) -> HeatMapFrame {
        let counted = traces.filter { $0.count > 0 }
        return HeatMapFrame(
            overlay: HeatMapOverlay(buckets: buckets, ways: ways, traces: counted, scale: scale), months: months,
            bucketCount: buckets.filter { $0.count > 0 }.count, traceCount: counted.count,
            maximumCount: max(buckets.map(\.count).max() ?? 0, counted.map(\.count).max() ?? 0), waysInArea: wayCount, isFiltered: filtered)
    }
}
