import FeatureStore
import GeoCore
import MapStyle

/// Builds a ``MapScene`` from a feature store file, a style and a viewport.
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

    private let file: FeatureStoreFile
    private let style: MapStyle

    /// Creates a builder.
    public init(file: FeatureStoreFile, style: MapStyle) {
        self.file = file
        self.style = style
    }

    /// Builds the scene for a viewport.
    ///
    /// - Throws: ``MapRenderError/noBands`` if the file holds no band, or a `FeatureStoreError` if a cell is damaged.
    public func scene(for viewport: MapViewport) throws -> MapScene {
        guard let band = ZoomBand.band(forZoom: viewport.zoom, available: file.bands) else { throw MapRenderError.noBands }
        let classIDs = style.visibleClassIDs(atZoom: viewport.zoom)
        let visible = ScreenBounds(width: viewport.width, height: viewport.height, margin: Self.cullingMargin)

        var linePieces: [LineKey: [LinePiece]] = [:]
        var lineInfo: [LineKey: (lanes: Int?, name: String?, structure: Structure)] = [:]
        var areas: [FeatureClass: [SceneArea]] = [:]
        var points: [FeatureClass: [ScenePoint]] = [:]

        let cells = viewport.cells(storageZoom: file.storageZoom, margin: Self.cullingMargin)
        var cellCount = 0
        for cell in cells {
            guard try file.containsCell(cell) else { continue }
            cellCount += 1
            for feature in try file.features(in: cell, band: band, classes: classIDs) {
                guard let featureClass = FeatureClass(rawValue: feature.classID) else { continue }
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
                        let usesLanes = style.style(for: featureClass)?.stroke?.width.ground != nil
                        lineInfo[key] = (usesLanes ? lanes(of: feature) : nil, name(of: feature), Structure(subclass: feature.subclass))
                    }
                case .area:
                    if let area = makeArea(feature, featureClass: featureClass, viewport: viewport, visible: visible) {
                        areas[featureClass, default: []].append(area)
                    }
                case .point:
                    for part in feature.parts {
                        guard let first = part.points.first else { continue }
                        let position = viewport.screenPoint(for: first)
                        guard ScreenBounds(of: [position])?.intersects(visible) == true else { continue }
                        points[featureClass, default: []].append(ScenePoint(
                            featureClass: featureClass, objectID: feature.objectID, position: position, name: name(of: feature)))
                    }
                }
            }
        }

        var joined: [(key: LineKey, info: (lanes: Int?, name: String?, structure: Structure), polyline: [PackedPoint])] = []
        // The ends of the lines that are drawn as bridges or tunnels: the lines on the ground that end there end flat.
        var structureEnds = Set<PackedPoint>()
        for (key, pieces) in linePieces {
            let info = lineInfo[key] ?? (nil, nil, .ground)
            let drawn = style.style(for: key.featureClass)?.drawnStructure(for: info.structure) ?? .ground
            for polyline in LineJoiner.join(pieces) {
                joined.append((key, info, polyline))
                if drawn != .ground, let first = polyline.first, let last = polyline.last {
                    structureEnds.insert(first)
                    structureEnds.insert(last)
                }
            }
        }
        var lines: [FeatureClass: [SceneLine]] = [:]
        for (key, info, polyline) in joined {
            let screen = polyline.map(viewport.screenPoint(for:))
            guard let bounds = ScreenBounds(of: screen), bounds.intersects(visible) else { continue }
            let onGround = (style.style(for: key.featureClass)?.drawnStructure(for: info.structure) ?? .ground) == .ground
            lines[key.featureClass, default: []].append(SceneLine(
                featureClass: key.featureClass, objectID: key.objectID, points: screen, lanes: info.lanes, name: info.name,
                structure: info.structure, flatStart: onGround && polyline.first.map(structureEnds.contains) == true,
                flatEnd: onGround && polyline.last.map(structureEnds.contains) == true))
        }
        // Dictionary order is not stable; sort so the same input always gives the same scene.
        for featureClass in lines.keys { lines[featureClass]?.sort { ($0.objectID, $0.points[0].x) < ($1.objectID, $1.points[0].x) } }
        for featureClass in areas.keys { areas[featureClass]?.sort { $0.objectID < $1.objectID } }
        for featureClass in points.keys { points[featureClass]?.sort { $0.objectID < $1.objectID } }

        var steps: [SceneStep] = []
        for step in style.drawSteps(atZoom: viewport.zoom) {
            let featureClass = step.featureClass
            // A line is drawn in the steps of the structure its class has a style for: a class with no bridge style draws
            // its bridges on the ground.
            let classStyle = style.style(for: featureClass)
            let stepLines = (lines[featureClass] ?? []).filter { classStyle?.drawnStructure(for: $0.structure) == step.structure }
            let sceneStep: SceneStep
            switch step.part {
            case .casing:
                sceneStep = SceneStep(step: step, lines: stepLines)
            case .body where step.structure == .ground:
                sceneStep = SceneStep(step: step, lines: stepLines, areas: areas[featureClass] ?? [], points: points[featureClass] ?? [])
            case .body:
                sceneStep = SceneStep(step: step, lines: stepLines)
            }
            if !sceneStep.lines.isEmpty || !sceneStep.areas.isEmpty || !sceneStep.points.isEmpty { steps.append(sceneStep) }
        }
        return MapScene(viewport: viewport, band: band, steps: steps, cellCount: cellCount, attribution: file.attribution)
    }

    // MARK: Areas

    private func makeArea(
        _ feature: StoredFeature, featureClass: FeatureClass, viewport: MapViewport, visible: ScreenBounds
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
            featureClass: featureClass, objectID: feature.objectID, rings: rings, outline: outline,
            name: name(of: feature), isIncomplete: feature.flags.contains(.incomplete))
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

    private func name(of feature: StoredFeature) -> String? {
        feature.nameID.flatMap { file.string(at: $0) }
    }

    /// The `lanes` tag as a positive integer. Tags exist in the detail band only.
    private func lanes(of feature: StoredFeature) -> Int? {
        for tag in feature.tags where file.string(at: tag.key) == "lanes" {
            guard let text = file.string(at: tag.value), let count = Int(text), count >= 1 else { return nil }
            return count
        }
        return nil
    }
}

private struct LineKey: Hashable {
    var featureClass: FeatureClass
    var objectID: Int64
    var type: StoredObjectType
}
