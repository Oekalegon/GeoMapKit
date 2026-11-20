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
/// It is for the phone and the Mac: the Watch has no heat map (question 64, H), and the lines of all runs are kept in memory, so an
/// overlay is made for the counts of an area, not for a whole country at once (see `maximumRuns`).
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
    /// The runs by cell of 0.01 degrees (about 1 km), so that a frame looks only at the runs near the view. A run that covers more
    /// cells than ``cellFillLimit`` is in `large` and looked at in every frame.
    private let grid: [GridCell: [Int]]
    private let large: [Int]

    private struct GridCell: Hashable {
        var x: Int
        var y: Int
    }

    private static let cellSize = 0.01
    private static let cellFillLimit = 256
    /// More cells than this in the view and the grid is not used (the view is a country: every run is looked at).
    private static let cellLookupLimit = 20_000

    /// The most runs an overlay keeps by default.
    public static let defaultMaximumRuns = 500_000

    /// How many runs were left out because there were more than `maximumRuns` (the lowest steps go first).
    public let droppedRunCount: Int

    /// How many runs the overlay draws (for tests).
    var runCount: Int { runs.count }

    /// Creates the overlay.
    ///
    /// - Parameters:
    ///   - buckets: The counts, one for each bucket of a way; buckets of ways that `ways` does not have are not drawn, and neither are
    ///     counts below the first step of the scale.
    ///   - ways: The geometry of the ways.
    ///   - scale: How a count looks.
    ///   - maximumRuns: The most runs to keep, which bounds the memory (a run is a few hundred bytes). If there are more, the runs of
    ///     the lowest steps are left out first and ``droppedRunCount`` says how many.
    public init(
        buckets: [HeatMapBucket], ways: HeatMapWays, scale: HeatMapScale = .standard, maximumRuns: Int = HeatMapOverlay.defaultMaximumRuns
    ) {
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
        var ordered = made.sorted { ($0.step, $0.south, $0.west) < ($1.step, $1.south, $1.west) }
        let limit = max(maximumRuns, 0)
        droppedRunCount = max(ordered.count - limit, 0)
        if droppedRunCount > 0 { ordered.removeFirst(droppedRunCount) }
        runs = ordered
        var cells: [GridCell: [Int]] = [:]
        var oversized: [Int] = []
        for (index, run) in ordered.enumerated() {
            let x0 = Self.cell(run.west), x1 = Self.cell(run.east), y0 = Self.cell(run.south), y1 = Self.cell(run.north)
            if (x1 - x0 + 1) * (y1 - y0 + 1) > Self.cellFillLimit {
                oversized.append(index)
            } else {
                for x in x0...x1 { for y in y0...y1 { cells[GridCell(x: x, y: y), default: []].append(index) } }
            }
        }
        grid = cells
        large = oversized
    }

    private static func cell(_ degrees: Double) -> Int { Int((degrees / cellSize).rounded(.down)) }

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
        for index in candidates(for: viewport, pad: pad) {
            let run = runs[index]
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

    /// The runs that may touch the view, in drawing order: those in the cells that the view covers and the large ones.
    private func candidates(for viewport: MapViewport, pad: Double) -> [Int] {
        // The geographic box of the view: its corners and the middle of its sides (a turned map).
        let xs = [-pad, viewport.width / 2, viewport.width + pad], ys = [-pad, viewport.height / 2, viewport.height + pad]
        let places = xs.flatMap { x in ys.map { viewport.coordinate(at: ScreenPoint(x: x, y: $0)) } }
        guard let south = places.map(\.latitude).min(), let north = places.map(\.latitude).max(),
            let west = places.map(\.longitude).min(), let east = places.map(\.longitude).max()
        else { return Array(runs.indices) }
        let x0 = Self.cell(west), x1 = Self.cell(east), y0 = Self.cell(south), y1 = Self.cell(north)
        // A view across the antimeridian or one that covers very many cells: look at every run.
        guard east >= west, (x1 - x0 + 1) * (y1 - y0 + 1) <= Self.cellLookupLimit else { return Array(runs.indices) }
        var found = Set(large)
        for x in x0...x1 { for y in y0...y1 { found.formUnion(grid[GridCell(x: x, y: y)] ?? []) } }
        return found.sorted()
    }
}
