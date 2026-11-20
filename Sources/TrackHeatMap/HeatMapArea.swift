import FeatureStore
import Foundation
import GeoCore
import TrackMatching
import TrackOverlays
import TrackStorage

/// The ways of an area of a map, joined to the store: what makes a heat map or a time-lapse of the counts in that area.
///
/// The ways come from the detail band of the map (a ``LineNetwork`` of the box), so the lines are as detailed as the map and the counts
/// of the store, which are along those ways, fall on them. Making the area reads the cells of the box once; after that an overlay is
/// made from the store alone. The area is not for a country: the overlay keeps every run in memory (see ``HeatMapOverlay``).
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
    ///   - scale: How a count looks; the same scale for two frames means the same colour for the same count.
    /// - Throws: ``TrackStoreError``.
    public func frame(
        categories: Set<String>? = nil, months: ClosedRange<TrackMonth>? = nil, measure: HeatMapMeasure = .activities,
        scale: HeatMapScale = .standard
    ) async throws -> HeatMapFrame {
        let counts = try await store.counts(ways: wayIDs, categories: categories, months: months)
        let buckets = counts.map { HeatMapBucket(wayID: $0.wayID, bucket: $0.bucket, count: measure == .passes ? $0.passes : $0.activities) }
        let stored = try await store.activityMonths(categories: categories)
        let fallback = TrackMonth(year: 1970, month: 1)
        let range = months ?? stored ?? fallback...fallback
        return Self.frame(buckets: buckets, ways: ways, months: range, scale: scale)
    }

    /// A time-lapse of the counts of some categories, month by month.
    ///
    /// - Parameters:
    ///   - categories: The categories to count, or `nil` for all.
    ///   - measure: What to count.
    ///   - scale: How a count looks; it is the same for every frame, so the colours of two months can be compared.
    /// - Returns: The time-lapse, or `nil` when the store has no activity in those categories.
    /// - Throws: ``TrackStoreError``.
    public func timeLapse(
        categories: Set<String>? = nil, measure: HeatMapMeasure = .activities, scale: HeatMapScale = .standard
    ) async throws -> HeatMapTimeLapse? {
        guard let range = try await store.activityMonths(categories: categories) else { return nil }
        let counts = try await store.monthlyCounts(ways: wayIDs, categories: categories, months: range)
        return HeatMapTimeLapse(range: range, counts: counts, measure: measure, ways: ways, scale: scale)
    }

    static func frame(buckets: [HeatMapBucket], ways: HeatMapWays, months: ClosedRange<TrackMonth>, scale: HeatMapScale) -> HeatMapFrame {
        HeatMapFrame(
            overlay: HeatMapOverlay(buckets: buckets, ways: ways, scale: scale), months: months,
            bucketCount: buckets.filter { $0.count > 0 }.count, maximumCount: buckets.map(\.count).max() ?? 0)
    }
}
