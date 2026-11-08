import FeatureStore
import Foundation
import OSMPBF

/// The built-up areas of an extract, for asking whether a footway lies in a town rather than in a park.
///
/// Many footways in a city are not beside a road: they cross a plaza, a station, a yard or a car park. They are the pavement of
/// the town, not paths to run. A footway is taken to be one when most of its length lies in a built-up area (urban land use, a
/// pedestrian area, a platform, a car park, a square) and not in a green one (a park, a garden, a wood, open land). Only
/// areas that are closed ways count; areas that are multipolygon relations are not seen.
struct TownIndex {
    /// The share of the footway's length that must lie in a town.
    static let minimumShare = 0.7
    /// A footway shorter than this, in metres, is not judged.
    static let minimumLength = 10.0
    private static let sampleSpacing = 5.0
    private static let cellSize = 100.0

    private struct Polygon {
        var xs: [Double], ys: [Double]
        var minX: Double, maxX: Double, minY: Double, maxY: Double

        func contains(x: Double, y: Double) -> Bool {
            guard x >= minX, x <= maxX, y >= minY, y <= maxY else { return false }
            var inside = false
            var j = xs.count - 1
            for i in 0..<xs.count {
                if (ys[i] > y) != (ys[j] > y), x < (xs[j] - xs[i]) * (y - ys[i]) / (ys[j] - ys[i]) + xs[i] { inside.toggle() }
                j = i
            }
            return inside
        }
    }

    private struct Layer {
        var polygons: [Polygon] = []
        var grid: [Int64: [Int]] = [:]

        mutating func add(_ polygon: Polygon) {
            let index = polygons.count
            polygons.append(polygon)
            for column in TownIndex.cell(polygon.minX)...TownIndex.cell(polygon.maxX) {
                for row in TownIndex.cell(polygon.minY)...TownIndex.cell(polygon.maxY) { grid[TownIndex.key(column, row), default: []].append(index) }
            }
        }

        func contains(x: Double, y: Double) -> Bool {
            (grid[TownIndex.key(TownIndex.cell(x), TownIndex.cell(y))] ?? []).contains { polygons[$0].contains(x: x, y: y) }
        }
    }

    private let projection: LocalMetres
    private var town = Layer()
    private var green = Layer()

    /// Builds the index from the closed ways of an extract.
    init(extract: OSMExtract, classifier: FeatureClassifier) {
        projection = LocalMetres(around: extract.boundingBox)
        for position in extract.ways.indices {
            let nodeIDs = extract.ways.nodeIDs(at: position)
            guard nodeIDs.count >= 4, nodeIDs.first == nodeIDs.last else { continue }
            let tags = extract.ways.tags(at: position)
            let classification = classifier.classify(tags, shape: .closedWay)
            let isPlatform = tags.value(forKey: "railway") == "platform" || tags.value(forKey: "public_transport") == "platform"
            let isTown = classification.kind == .area
                && (classification.featureClass == .landuseUrban || classification.featureClass == .roadArea
                    || tags.value(forKey: "amenity") == "parking" || tags.value(forKey: "place") == "square")
            let isGreen = classification.kind == .area
                && (classification.featureClass == .landcover || classification.featureClass == .forest)
            guard isTown || isPlatform || isGreen else { continue }
            let (runs, gaps) = FeatureStoreBuilder.runs(ofWayAt: position, in: extract)
            guard gaps == 0, runs.count == 1, runs[0].count >= 4 else { continue }
            let points = runs[0].map { projection.project($0) }
            let polygon = Polygon(
                xs: points.map(\.x), ys: points.map(\.y), minX: points.map(\.x).min() ?? 0, maxX: points.map(\.x).max() ?? 0,
                minY: points.map(\.y).min() ?? 0, maxY: points.map(\.y).max() ?? 0)
            if isGreen && !isTown { green.add(polygon) } else { town.add(polygon) }
        }
    }

    /// Whether most of a footway lies in a built-up area and not in a green one.
    ///
    /// - Parameter runs: The footway's points, one array per piece (a way with a gap has two).
    func isInTown(_ runs: [[PackedPoint]]) -> Bool {
        var total = 0.0, inside = 0.0
        for run in runs where run.count >= 2 {
            for index in 0..<(run.count - 1) {
                let a = projection.project(run[index]), b = projection.project(run[index + 1])
                let length = ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
                guard length > 0 else { continue }
                let samples = max(1, Int((length / Self.sampleSpacing).rounded(.up)))
                let weight = length / Double(samples)
                for sample in 0..<samples {
                    let t = (Double(sample) + 0.5) / Double(samples)
                    let x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t
                    total += weight
                    if town.contains(x: x, y: y) && !green.contains(x: x, y: y) { inside += weight }
                }
            }
        }
        return total >= Self.minimumLength && inside >= Self.minimumShare * total
    }

    fileprivate static func cell(_ value: Double) -> Int { Int((value / cellSize).rounded(.down)) }
    fileprivate static func key(_ column: Int, _ row: Int) -> Int64 { (Int64(column) << 32) ^ (Int64(row) & 0xFFFF_FFFF) }
}
