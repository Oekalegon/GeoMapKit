import FeatureStore
import Foundation
import MapStyle

/// Collects the named features of a scene that have a label style.
///
/// Points are labelled next to their symbol and areas at the centre of their bounding box when that lies in the view.
/// Lines are labelled along their course, see ``collectLines(from:style:)``.
enum LabelCandidates {
    /// The named lines of a scene whose class has a label style: roads, rivers, paths, borders.
    static func collectLines(from scene: MapScene, style: MapStyle) -> [LineLabelCandidate] {
        let zoom = scene.viewport.zoom
        var candidates: [LineLabelCandidate] = []
        for step in scene.steps where step.step.part == .body {
            guard let label = style.style(for: step.step.featureClass)?.label else { continue }
            let size = label.size.value(atZoom: zoom)
            guard size > 0, label.visibleZoom.contains(zoom) else { continue }
            for line in step.lines {
                guard let name = line.name, !name.isEmpty, line.points.count >= 2 else { continue }
                candidates.append(LineLabelCandidate(
                    objectID: line.objectID, text: name, points: line.points, fontSize: size, style: label))
            }
        }
        return candidates
    }

    /// The population taken for a place that has no `population` tag, by its rank: the `place` subclasses are 1 city, 2 town and 3 village
    /// (see the rule table), and the rest (hamlets and the like) are smaller still.
    static func assumedPopulation(of subclass: UInt8) -> Int {
        let city: UInt8 = 1, town: UInt8 = 2, village: UInt8 = 3
        switch subclass {
        case city: return 200_000
        case town: return 20_000
        case village: return 2_000
        default: return 500
        }
    }

    static func collect(from scene: MapScene, style: MapStyle) -> [LabelCandidate] {
        let zoom = scene.viewport.zoom
        // The part of the viewport that is seen: a frame is drawn with a margin, and a name in the margin is never seen.
        let view = ScreenBounds(width: scene.viewport.width, height: scene.viewport.height, margin: -scene.viewport.labelInset)
        var candidates: [LabelCandidate] = []
        for step in scene.steps where step.step.part == .body {
            guard let classStyle = style.style(for: step.step.featureClass), let label = classStyle.label else { continue }
            let size = label.size.value(atZoom: zoom)
            guard size > 0, label.visibleZoom.contains(zoom) else { continue }
            // The larger places first (the lower subclass, then the greater population); a place within the thinning radius of one that
            // has its name gets none.
            let radius = label.thinningRadius.value(atZoom: zoom)
            // The largest place in view (the names of the sizes are relative to it).
            let largest = label.populationScale == nil ? 0 : step.points.reduce(0) { best, point in
                ScreenBounds(of: [point.position])?.intersects(view) == true
                    ? max(best, point.population ?? Self.assumedPopulation(of: point.subclass)) : best
            }
            var named: [ScenePoint] = []
            let ranked = radius > 0
                ? step.points.sorted {
                    ($0.subclass, -($0.population ?? 0), $0.objectID) < ($1.subclass, -($1.population ?? 0), $1.objectID)
                }
                : step.points
            for point in ranked {
                guard let name = point.name, !name.isEmpty else { continue }
                if radius > 0 {
                    // A city is hidden only by a city (the cities are ranked first) within the shorter radius.
                    let reach = point.subclass == 1 ? radius * label.cityThinningFactor : radius
                    let near = named.contains { hypot($0.position.x - point.position.x, $0.position.y - point.position.y) < reach }
                    if near { continue }
                    named.append(point)
                }
                let symbolRadius = classStyle.point?.radius.value(atZoom: zoom) ?? 0
                var pointSize = size
                if let scale = label.populationScale {
                    pointSize *= scale.scale(
                        population: point.population ?? Self.assumedPopulation(of: point.subclass), largest: largest, atZoom: zoom)
                }
                candidates.append(LabelCandidate(
                    objectID: point.objectID, text: name, anchor: point.position, symbolRadius: symbolRadius, fontSize: pointSize, style: label))
            }
            // One label per area, for the area as a whole: the pieces that the cells cut it into are taken together. The name goes at the
            // point of the part in view that is farthest from the real shore (the edges that the clip made along the cell borders are no
            // shore), so it is in the water also for a bent lake or one with many islands. An area is named only when its pieces in the
            // scene together cover `minimumArea` square points (the boxes of the pieces are added up).
            struct Pieces {
                var name = ""
                var rings: [[ScreenPoint]] = []
                var shore: [[ScreenPoint]] = []
                var total = 0.0
            }
            var byObject: [Int64: Pieces] = [:]
            for area in step.areas {
                guard let name = area.name, !name.isEmpty, let bounds = ScreenBounds(of: area.rings.joined()) else { continue }
                var pieces = byObject[area.objectID] ?? Pieces(name: name)
                pieces.rings += area.rings
                pieces.shore += area.outline
                pieces.total += (bounds.maxX - bounds.minX) * (bounds.maxY - bounds.minY)
                byObject[area.objectID] = pieces
            }
            for (objectID, pieces) in byObject.sorted(by: { $0.key < $1.key }) where pieces.total >= label.minimumArea {
                // The name is about as wide as its characters: keep its middle away from the edge of the view.
                let halfWidth = Double(pieces.name.count) * size * 0.3, halfHeight = size * 0.6
                let domain = ScreenBounds(
                    minX: view.minX + halfWidth, minY: view.minY + halfHeight, maxX: view.maxX - halfWidth, maxY: view.maxY - halfHeight)
                guard let found = PolygonLabelPoint.find(in: pieces.rings, edges: pieces.shore, domain: domain) else { continue }
                candidates.append(LabelCandidate(
                    objectID: objectID, text: pieces.name, anchor: found.point, symbolRadius: 0, fontSize: size, style: label,
                    extent: pieces.total, fitWidth: 2 * found.distance))
            }
        }
        return candidates
    }
}
