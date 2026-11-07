import FeatureStore
import MapStyle

/// Collects the named features of a scene that have a label style.
///
/// Points are labelled next to their symbol and areas at the centre of their bounding box when that lies in the view.
/// Lines are not labelled yet: curved text along paths comes later (see "Renderer scope" in the architecture document).
enum LabelCandidates {
    static func collect(from scene: MapScene, style: MapStyle) -> [LabelCandidate] {
        let zoom = scene.viewport.zoom
        let view = ScreenBounds(width: scene.viewport.width, height: scene.viewport.height, margin: 0)
        var candidates: [LabelCandidate] = []
        for step in scene.steps where step.step.part == .body {
            guard let classStyle = style.style(for: step.step.featureClass), let label = classStyle.label else { continue }
            let size = label.size.value(atZoom: zoom)
            guard size > 0 else { continue }
            for point in step.points {
                guard let name = point.name, !name.isEmpty else { continue }
                let radius = classStyle.point?.radius.value(atZoom: zoom) ?? 0
                candidates.append(LabelCandidate(
                    objectID: point.objectID, text: name, anchor: point.position, symbolRadius: radius, fontSize: size, style: label))
            }
            // One label per area: the piece with the largest box wins, so a lake that spans cells is named once.
            var largest: [Int64: LabelCandidate] = [:]
            for area in step.areas {
                guard let name = area.name, !name.isEmpty, let bounds = ScreenBounds(of: area.rings.joined()) else { continue }
                let centre = ScreenPoint(x: (bounds.minX + bounds.maxX) / 2, y: (bounds.minY + bounds.maxY) / 2)
                guard ScreenBounds(of: [centre])?.intersects(view) == true else { continue }
                let extent = (bounds.maxX - bounds.minX) * (bounds.maxY - bounds.minY)
                if let existing = largest[area.objectID], existing.extent >= extent { continue }
                largest[area.objectID] = LabelCandidate(
                    objectID: area.objectID, text: name, anchor: centre, symbolRadius: 0, fontSize: size, style: label,
                    extent: extent)
            }
            candidates.append(contentsOf: largest.values)
        }
        return candidates
    }
}
