import Foundation
import GeoCore
import MapRender

/// Draws how often the ways of a map were used: the heat map of the track store.
///
/// Each bucket of a way (10 m) is a count; neighbouring buckets on a step of the scale are drawn as one line, the colour and the width
/// come from the step (``HeatMapScale``), and the busiest buckets are drawn last, over the others. The lines lie on the ways of the map
/// (the geometry of ``HeatMapWays``), so they are as detailed as the map. The scale is fixed: it does not depend on the highest count,
/// so two overlays (two months, two categories) mean the same by a colour.
///
/// The overlay is immutable and has one id for its life; a new filter makes a new overlay. The lines are made when it is created, so the
/// work in `items(for:)` is projecting and clipping only the runs that touch the view.
public final class HeatMapOverlay: MapOverlay, Sendable {
    public let overlayID = UUID()
    /// The scale that gives each count its look.
    public let scale: HeatMapScale

    /// A run of buckets of one way on one step of the scale, as lines.
    private struct Run: Sendable {
        var step: Int
        var parts: [[Coordinate]]
        var south: Double, west: Double, north: Double, east: Double
    }

    private let runs: [Run]

    /// How many runs the overlay draws (for tests).
    var runCount: Int { runs.count }

    /// Creates the overlay.
    ///
    /// - Parameters:
    ///   - buckets: The counts, one for each bucket of a way; buckets of ways that `ways` does not have are not drawn, and neither are
    ///     counts below the first step of the scale.
    ///   - ways: The geometry of the ways.
    ///   - scale: How a count looks.
    public init(buckets: [HeatMapBucket], ways: HeatMapWays, scale: HeatMapScale = .standard) {
        self.scale = scale
        var byWay: [Int64: [HeatMapBucket]] = [:]
        for bucket in buckets where bucket.count > 0 && bucket.bucket >= 0 { byWay[bucket.wayID, default: []].append(bucket) }
        var made: [Run] = []
        for (way, list) in byWay where ways.contains(way: way) {
            let sorted = list.sorted { $0.bucket < $1.bucket }
            var first = 0
            while first < sorted.count {
                guard let step = scale.stepIndex(for: sorted[first].count) else {
                    first += 1
                    continue
                }
                // Buckets that follow each other on the same step are one run.
                var last = first
                while last + 1 < sorted.count, sorted[last + 1].bucket == sorted[last].bucket + 1,
                    scale.stepIndex(for: sorted[last + 1].count) == step
                {
                    last += 1
                }
                let length = HeatMapBucket.bucketLength
                let parts = ways.lines(way: way, from: Double(sorted[first].bucket) * length, to: Double(sorted[last].bucket + 1) * length)
                if let run = Self.run(step: step, parts: parts) { made.append(run) }
                first = last + 1
            }
        }
        // The busiest last, so that they are drawn over the others; the way and the place fix the order of equal steps.
        runs = made.sorted { ($0.step, $0.south, $0.west) < ($1.step, $1.south, $1.west) }
    }

    private static func run(step: Int, parts: [[Coordinate]]) -> Run? {
        let all = parts.joined()
        guard let first = all.first else { return nil }
        var run = Run(step: step, parts: parts, south: first.latitude, west: first.longitude, north: first.latitude, east: first.longitude)
        for point in all {
            run.south = min(run.south, point.latitude)
            run.north = max(run.north, point.latitude)
            run.west = min(run.west, point.longitude)
            run.east = max(run.east, point.longitude)
        }
        return run
    }

    public func items(for viewport: MapViewport) -> [OverlayItem] {
        let widest = scale.steps.map(\.style.width).max() ?? 0
        let pad = widest + 4
        let area = PolylineClipper.Rectangle(minX: -pad, minY: -pad, maxX: viewport.width + pad, maxY: viewport.height + pad)
        var items: [OverlayItem] = []
        for run in runs {
            // Skip a run whose box is outside the view: the box corners on the screen (a turned map makes the box a diamond, so the
            // screen box of its corners is used).
            let corners = [(run.south, run.west), (run.south, run.east), (run.north, run.west), (run.north, run.east)].map {
                viewport.screenPoint(for: Coordinate(latitude: $0.0, longitude: $0.1))
            }
            let xs = corners.map(\.x), ys = corners.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(),
                maxX >= area.minX, minX <= area.maxX, maxY >= area.minY, minY <= area.maxY
            else { continue }
            let style = scale.steps[run.step].style
            for part in run.parts {
                let screen = part.map { viewport.screenPoint(for: $0) }
                for clipped in PolylineClipper.clip(screen, to: area) { items.append(.line(OverlayLine(points: clipped, style: style))) }
            }
        }
        return items
    }
}
