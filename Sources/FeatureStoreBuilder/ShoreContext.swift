import FeatureStore
import OSMPBF

/// What the builder needs to know about water and coast to draw their lines in the right places.
///
/// Four things go wrong where land, river and sea meet, and each has its answer here:
/// - the outline of a lake, a fjord or a wide river is a line of its own (`waterEdge`), left out where it lies on a coastline,
///   which draws that stretch itself;
/// - the coastline that closes a river mouth runs through the water of the river, and is left out there;
/// - the centre line of a river (`waterway=river`) is left out where it lies in the river's own area;
/// - the border of a protected area is drawn in another colour where it lies in the sea.
///
/// The indexes are built when they are first needed, so an extract with no water pays nothing.
struct ShoreContext {
    /// How far apart the samples of a line are, in metres.
    static let spacing = 25.0
    /// How near an outline must be to a coastline, in metres, to lie on it. The outline of a river and the coastline along it are
    /// often mapped a few metres apart.
    static let coastTolerance = 6.0
    /// How far to each side of an outline, in metres, to look for water: an outline with water on both sides is no shore.
    static let sideOffset = 3.0
    /// How far to the left of a coastline, in metres, the water of a river mouth is looked for: at both distances. The outline of a
    /// river and its coastline are often mapped a few metres apart, so a point near the shore is no proof; one that is 10 and 20
    /// metres inland in the water of the river is.
    static let landSide = [10.0, 20.0]

    private let extract: OSMExtract
    private let classifier: FeatureClassifier
    private let projection: LocalMetres
    private var coastGrid: SegmentGrid?
    private var waterLayer: AreaLayer?
    private var largeWaterLayer: AreaLayer?
    /// The sea of the stored area, or `nil` if there is none.
    var sea: SeaLookup?

    init(extract: OSMExtract, classifier: FeatureClassifier) {
        self.extract = extract
        self.classifier = classifier
        projection = LocalMetres(around: extract.boundingBox)
    }

    private mutating func coast() -> SegmentGrid {
        if let coastGrid { return coastGrid }
        var grid = SegmentGrid()
        for position in extract.ways.indices where extract.ways.tags(at: position).value(forKey: "natural") == "coastline" {
            for run in FeatureStoreBuilder.runs(ofWayAt: position, in: extract).runs { grid.add(points: run.map { projection.project($0) }) }
        }
        coastGrid = grid
        return grid
    }

    private mutating func water() -> AreaLayer {
        if let waterLayer { return waterLayer }
        var layer = AreaLayer()
        let areas = AreaPolygons.collect(extract: extract, classifier: classifier) { classification, _ -> Bool? in
            classification.featureClass == .waterArea && classification.kind == .area ? true : nil
        }
        for area in areas { layer.add(area.polygon) }
        waterLayer = layer
        return layer
    }

    /// The water areas that are in the overview band (not thin, not small, see `WaterSize`): where a river runs in one of these its
    /// centre line is not drawn, because the area is. A river in a thin area keeps its line, since the area is not drawn at low zoom.
    private mutating func largeWater() -> AreaLayer {
        if let largeWaterLayer { return largeWaterLayer }
        var layer = AreaLayer()
        let areas = AreaPolygons.collect(extract: extract, classifier: classifier) { classification, _ -> Bool? in
            classification.featureClass == .waterArea && classification.kind == .area ? true : nil
        }
        for area in areas where !WaterSize.isSmall(area.polygon) { layer.add(area.polygon) }
        largeWaterLayer = layer
        return layer
    }

    /// The outline of a water area without the stretches that lie on a coastline, and without those that have water on both sides
    /// (the line where two water areas meet, which is no shore).
    mutating func outline(of rings: [[PackedPoint]]) -> [[PackedPoint]] {
        let coast = coast()
        let water = water()
        return LineSplitter.removing(from: rings, projection: projection, spacing: Self.spacing) { sample in
            if coast.isNear(x: sample.x, y: sample.y, tolerance: Self.coastTolerance) { return true }
            let dx = -sample.directionY * Self.sideOffset, dy = sample.directionX * Self.sideOffset
            return water.contains(x: sample.x + dx, y: sample.y + dy) && water.contains(x: sample.x - dx, y: sample.y - dy)
        }.kept
    }

    /// A coastline without the stretches that run through the water of a river: those with a water area on the land side.
    mutating func coastline(_ lines: [[PackedPoint]]) -> (kept: [[PackedPoint]], dropped: Int) {
        let water = water()
        guard !water.polygons.isEmpty else { return (lines, 0) }
        return LineSplitter.removing(from: lines, projection: projection, spacing: Self.spacing) { sample in
            Self.landSide.allSatisfy {
                water.contains(x: sample.x - sample.directionY * $0, y: sample.y + sample.directionX * $0)
            }
        }
    }

    /// A river or stream without the stretches that lie in a water area.
    mutating func waterLine(_ lines: [[PackedPoint]]) -> (kept: [[PackedPoint]], dropped: Int) {
        let water = water()
        guard !water.polygons.isEmpty else { return (lines, 0) }
        return LineSplitter.removing(from: lines, projection: projection, spacing: Self.spacing) { water.contains(x: $0.x, y: $0.y) }
    }

    /// A river or stream split into the stretches outside the water areas and the stretches inside them.
    mutating func waterLineStretches(_ lines: [[PackedPoint]]) -> (kept: [[PackedPoint]], inWater: [[PackedPoint]]) {
        let water = largeWater()
        guard !water.polygons.isEmpty else { return (lines, []) }
        var kept: [[PackedPoint]] = [], inWater: [[PackedPoint]] = []
        for line in lines {
            for stretch in LineSplitter.split(line, projection: projection, spacing: Self.spacing, test: { water.contains(x: $0.x, y: $0.y) })
            where stretch.points.count >= 2 {
                if stretch.answer { inWater.append(stretch.points) } else { kept.append(stretch.points) }
            }
        }
        return (kept, inWater)
    }

    /// The border of a protected area, split into what lies on land and what lies in the sea.
    func parkBorder(_ lines: [[PackedPoint]]) -> (land: [[PackedPoint]], sea: [[PackedPoint]]) {
        guard let sea else { return (lines, []) }
        var land: [[PackedPoint]] = [], inSea: [[PackedPoint]] = []
        for line in lines {
            for stretch in LineSplitter.split(line, projection: projection, spacing: Self.spacing, test: { sea.contains($0.point) }) where stretch.points.count >= 2 {
                if stretch.answer { inSea.append(stretch.points) } else { land.append(stretch.points) }
            }
        }
        return (land, inSea)
    }
}
