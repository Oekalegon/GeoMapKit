import FeatureStore
import GeoCore
import MapStyle

/// Builds a ``MapScene`` from a feature store (one file, or a set of block files), a style and a viewport.
///
/// The builder reads only what is needed: the cells that touch the view, one band, and the classes the style shows
/// at this zoom (the rest is skipped by length in the file). It then
/// - joins the pieces of lines that were cut at cell borders,
/// - projects to screen points,
/// - drops features that are completely off screen, and
/// - orders everything by the style's draw steps.
///
/// The scene is rebuilt, not updated, when the viewport changes. On the Watch the app should rebuild only when the
/// position leaves the cached area or the zoom changes (see "Battery" in the architecture document).
public struct MapSceneBuilder: Sendable {
    /// The extra margin, in points, around the view for culling and for the cells read. It covers the widest stroke.
    public static let cullingMargin = 64.0

    private let source: any CellSource
    private let style: MapStyle

    /// Creates a builder that reads one store file.
    public init(file: FeatureStoreFile, style: MapStyle) {
        source = file
        self.style = style
    }

    /// Creates a builder that reads cells from a source: one file or a set of block files.
    ///
    /// Each cell is read from the file that holds it, and its names and tags are looked up in that file's own string table. Lines
    /// that run from one file into another are joined like lines that run from one cell into the next.
    public init(source: any CellSource, style: MapStyle) {
        self.source = source
        self.style = style
    }

    /// Builds the scene for a viewport.
    ///
    /// - Throws: ``MapRenderError/noBands`` if the file holds no band, or a `FeatureStoreError` if a cell is damaged.
    public func scene(for viewport: MapViewport) throws -> MapScene {
        // A set with coarse levels hands out the level that serves this zoom; the cells below are read from it.
        let source = self.source.source(atZoom: viewport.zoom)
        guard let band = ZoomBand.band(forZoom: viewport.zoom, available: source.bands) else { throw MapRenderError.noBands }
        let classIDs = style.visibleClassIDs(atZoom: viewport.zoom)
        let visible = ScreenBounds(width: viewport.width, height: viewport.height, margin: Self.cullingMargin)

        var linePieces: [LineKey: [LinePiece]] = [:]
        var lineInfo: [LineKey: (lanes: Int?, name: String?, structure: Structure, flow: Int, variant: Int?)] = [:]
        var areas: [StepKey: [SceneArea]] = [:]
        var points: [StepKey: [ScenePoint]] = [:]

        let cells = viewport.cells(storageZoom: source.storageZoom, margin: Self.cullingMargin)
        var cellCount = 0
        for cell in cells {
            guard let file = try source.file(containing: cell) else { continue }
            cellCount += 1
            for feature in try file.features(in: cell, band: band, classes: classIDs) {
                guard let featureClass = FeatureClass(rawValue: feature.classID) else { continue }
                // A hidden variant is dropped here, before it can join lines, taper road ends or count as a road in a divided road.
                let variant = variantIndex(of: feature, class: featureClass, in: file)
                if let variant, style.style(for: featureClass)?.variants[variant].hidden == true { continue }
                switch feature.kind {
                case .line:
                    let key = LineKey(featureClass: featureClass, objectID: feature.objectID, type: feature.objectType)
                    for part in feature.parts {
                        linePieces[key, default: []].append(LinePiece(
                            points: part.points, continuesBefore: feature.flags.contains(.continuesBefore),
                            continuesAfter: feature.flags.contains(.continuesAfter), offset: feature.offsetAlongLine))
                    }
                    if lineInfo[key] == nil {
                        // Tags are looked up only where the style uses them: `lanes` for classes with a ground width.
                        let usesLanes = style.style(for: featureClass, variant: variant)?.stroke?.width.ground != nil
                        let road = usesLanes ? roadTags(of: feature, in: file) : (lanes: nil, flow: 0)
                        lineInfo[key] = (road.lanes, name(of: feature, in: file), Structure(subclass: feature.subclass), road.flow, variant)
                    }
                case .area:
                    if var area = makeArea(feature, in: file, featureClass: featureClass, viewport: viewport, visible: visible) {
                        area.variant = variant
                        areas[StepKey(featureClass: featureClass, variant: area.variant), default: []].append(area)
                    }
                case .point:
                    for part in feature.parts {
                        guard let first = part.points.first else { continue }
                        let position = viewport.screenPoint(for: first)
                        guard ScreenBounds(of: [position])?.intersects(visible) == true else { continue }
                        var point = ScenePoint(
                            featureClass: featureClass, objectID: feature.objectID, position: position, name: name(of: feature, in: file),
                            subclass: feature.subclass, population: featureClass == .place ? population(of: feature, in: file) : nil)
                        point.variant = variant
                        points[StepKey(featureClass: featureClass, variant: point.variant), default: []].append(point)
                    }
                }
            }
        }

        var joined: [(key: LineKey, info: (lanes: Int?, name: String?, structure: Structure, flow: Int, variant: Int?), polyline: [PackedPoint])] = []
        // The ends of the lines that are drawn as bridges or tunnels: the lines on the ground that end there end flat.
        var structureEnds = Set<PackedPoint>()
        // The vertices in the middle of the roads: a road that ends at one meets another road side on (a T junction).
        var throughPoints = Set<PackedPoint>()
        for (key, pieces) in linePieces {
            let info = lineInfo[key] ?? (nil, nil, .ground, 0, nil)
            let classStyle = style.style(for: key.featureClass, variant: info.variant)
            let drawn = classStyle?.drawnStructure(for: info.structure) ?? .ground
            let isRoad = classStyle?.stroke?.width.ground != nil
            for polyline in LineJoiner.join(pieces) {
                joined.append((key, info, polyline))
                if drawn != .ground, let first = polyline.first, let last = polyline.last {
                    structureEnds.insert(first)
                    structureEnds.insert(last)
                }
                if isRoad, polyline.count > 2 { throughPoints.formUnion(polyline[1..<(polyline.count - 1)]) }
            }
        }
        var built: [SceneLine] = []
        var ends: [(start: PackedPoint?, end: PackedPoint?)] = []
        var roadWidths: [Double?] = []
        var flows: [Int] = []
        for (key, info, polyline) in joined {
            let screen = polyline.map(viewport.screenPoint(for:))
            guard let bounds = ScreenBounds(of: screen), bounds.intersects(visible) else { continue }
            let classStyle = style.style(for: key.featureClass, variant: info.variant)
            let onGround = (classStyle?.drawnStructure(for: info.structure) ?? .ground) == .ground
            let isRoad = classStyle?.stroke?.width.ground != nil
            // A road ends flat where a bridge or a tunnel starts, and where it meets the side of another road.
            func endsFlat(_ end: PackedPoint?) -> Bool {
                guard onGround, let end else { return false }
                return structureEnds.contains(end) || (isRoad && throughPoints.contains(end))
            }
            var sceneLine = SceneLine(
                featureClass: key.featureClass, objectID: key.objectID, points: screen, lanes: info.lanes, name: info.name,
                structure: info.structure, flatStart: endsFlat(polyline.first), flatEnd: endsFlat(polyline.last))
            sceneLine.variant = info.variant
            built.append(sceneLine)
            ends.append((polyline.first, polyline.last))
            flows.append(info.flow)
            roadWidths.append(classStyle?.stroke?.width.ground == nil ? nil : classStyle?.stroke?.width.resolved(
                atZoom: viewport.zoom, metresPerPoint: viewport.metresPerPoint, lanes: info.lanes))
        }
        RoadTaper.apply(to: &built, nodes: ends, widths: roadWidths)
        // The strips between the carriageways of divided roads (one-way ways side by side; the `oneway` tag is in the detail band).
        var medians: [StepKey: [SceneMedian]] = [:]
        for strip in DividedRoads.medians(lines: built, flows: flows, widths: roadWidths, metresPerPoint: viewport.metresPerPoint) {
            medians[StepKey(featureClass: strip.featureClass, variant: strip.variant), default: []].append(strip)
        }
        var lines: [StepKey: [SceneLine]] = [:]
        for line in built { lines[StepKey(featureClass: line.featureClass, variant: line.variant), default: []].append(line) }
        // Dictionary order is not stable; sort so the same input always gives the same scene.
        for key in lines.keys { lines[key]?.sort { ($0.objectID, $0.points[0].x) < ($1.objectID, $1.points[0].x) } }
        for key in areas.keys { areas[key]?.sort { $0.objectID < $1.objectID } }
        for key in points.keys { points[key]?.sort { $0.objectID < $1.objectID } }

        var steps: [SceneStep] = []
        for step in style.drawSteps(atZoom: viewport.zoom) {
            let key = StepKey(featureClass: step.featureClass, variant: step.variant)
            // A line is drawn in the steps of the structure its class has a style for: a class with no bridge style draws
            // its bridges on the ground.
            let classStyle = style.style(for: step)
            let stepLines = (lines[key] ?? []).filter { classStyle?.drawnStructure(for: $0.structure) == step.structure }
            let sceneStep: SceneStep
            let stepMedians = (medians[key] ?? []).filter { classStyle?.drawnStructure(for: $0.structure) == step.structure }
            switch step.part {
            case .casing:
                sceneStep = SceneStep(step: step, lines: stepLines)
            case .body where step.structure == .ground:
                sceneStep = SceneStep(
                    step: step, lines: stepLines, areas: areas[key] ?? [], points: points[key] ?? [],
                    medians: stepMedians)
            case .body:
                sceneStep = SceneStep(step: step, lines: stepLines, medians: stepMedians)
            }
            if !sceneStep.lines.isEmpty || !sceneStep.areas.isEmpty || !sceneStep.points.isEmpty || !sceneStep.medians.isEmpty { steps.append(sceneStep) }
        }
        return MapScene(viewport: viewport, band: band, steps: steps, cellCount: cellCount, attribution: source.attribution)
    }

    // MARK: Areas

    private func makeArea(
        _ feature: StoredFeature, in file: FeatureStoreFile, featureClass: FeatureClass, viewport: MapViewport, visible: ScreenBounds
    ) -> SceneArea? {
        var rings: [[ScreenPoint]] = []
        var outline: [[ScreenPoint]] = []
        for part in feature.parts where part.points.count >= 3 {
            let screen = part.points.map(viewport.screenPoint(for:))
            rings.append(screen)
            outline.append(contentsOf: Self.realEdgeRuns(of: screen, artificial: part.artificialEdges))
        }
        guard let bounds = ScreenBounds(of: rings.joined()), bounds.intersects(visible) else { return nil }
        return SceneArea(
            featureClass: featureClass, objectType: feature.objectType, objectID: feature.objectID, rings: rings, outline: outline,
            name: name(of: feature, in: file), isIncomplete: feature.flags.contains(.incomplete))
    }

    /// Splits a ring into runs of consecutive edges that are not artificial.
    ///
    /// Edge `i` runs from `points[i]` to `points[i + 1]`. A ring with no artificial edge is returned as one closed run.
    static func realEdgeRuns(of points: [ScreenPoint], artificial: [Range<Int>]) -> [[ScreenPoint]] {
        let edgeCount = points.count - 1
        guard edgeCount >= 1 else { return [] }
        var isArtificial = [Bool](repeating: false, count: edgeCount)
        for range in artificial {
            for edge in range.clamped(to: 0..<edgeCount) { isArtificial[edge] = true }
        }
        var runs: [[ScreenPoint]] = []
        var current: [ScreenPoint] = []
        for edge in 0..<edgeCount {
            if isArtificial[edge] {
                if current.count >= 2 { runs.append(current) }
                current = []
            } else {
                if current.isEmpty { current.append(points[edge]) }
                current.append(points[edge + 1])
            }
        }
        if current.count >= 2 { runs.append(current) }
        // A closed ring starts mid-run when its first and last edges are both real: join the two halves.
        if runs.count >= 2, !isArtificial[0], !isArtificial[edgeCount - 1], points[0] == points[edgeCount],
           let last = runs.popLast()
        {
            runs[0] = last + runs[0].dropFirst()
        }
        return runs
    }

    // MARK: Tags

    /// The name of a feature, from the string table of the file the feature was read from.
    private func name(of feature: StoredFeature, in file: FeatureStoreFile) -> String? {
        feature.nameID.flatMap { file.string(at: $0) }
    }

    /// The tags of a road that the scene uses, read in one pass: the `lanes` tag as a positive integer (or `nil`), and the direction of
    /// a one-way road (1 along the vertices of the way, -1 against them, 0 for a two-way road, a roundabout, or no tags; a motorway is one-way without a tag). Tags exist in
    /// the detail band only.
    /// The `population` tag of a place (it is kept in every band), read as a number.
    private func population(of feature: StoredFeature, in file: FeatureStoreFile) -> Int? {
        for tag in feature.tags where file.string(at: tag.key) == "population" {
            return PlacePopulation.population(file.string(at: tag.value))
        }
        return nil
    }

    /// The index of the variant of the class that the feature is in, or `nil`. Tags are read only for a class whose variants have tag
    /// conditions; a band that does not hold a tag does not have it for the condition.
    private func variantIndex(of feature: StoredFeature, class featureClass: FeatureClass, in file: FeatureStoreFile) -> Int? {
        guard let classStyle = style.style(for: featureClass), !classStyle.variants.isEmpty else { return nil }
        let needsTags = classStyle.variants.contains { !$0.tags.isEmpty }
        return classStyle.variantIndex(subclass: feature.subclass, in: featureClass) { key in
            guard needsTags else { return nil }
            for tag in feature.tags where file.string(at: tag.key) == key { return file.string(at: tag.value) }
            return nil
        }
    }

    private func roadTags(of feature: StoredFeature, in file: FeatureStoreFile) -> (lanes: Int?, flow: Int) {
        var lanes: Int?
        var oneway: String?
        var junction: String?
        var highway: String?
        for tag in feature.tags {
            switch file.string(at: tag.key) {
            case "lanes":
                if let text = file.string(at: tag.value), let count = Int(text), count >= 1 { lanes = count }
            case "oneway":
                oneway = file.string(at: tag.value)
            case "junction":
                junction = file.string(at: tag.value)
            case "highway":
                highway = file.string(at: tag.value)
            default:
                break
            }
        }
        // A roundabout is one-way whatever else it says, but its sides are no carriageways of a divided road.
        guard junction != "roundabout" else { return (lanes, 0) }
        return (lanes, OnewayRule.flow(oneway: oneway, highway: highway, junction: junction))
    }
}

private struct LineKey: Hashable {
    var featureClass: FeatureClass
    var objectID: Int64
    var type: StoredObjectType
}

/// A class and one of its variants (`nil` for the features of the class that are in none).
private struct StepKey: Hashable {
    var featureClass: FeatureClass
    var variant: Int?
}
