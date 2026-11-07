/// Chooses where labels go so that none overlaps another label or a point symbol.
///
/// Greedy and deterministic: candidates are tried in order of priority (highest first, then OSM ID), and each takes
/// the first of its positions that is free and inside the view. A candidate with no free position is dropped.
/// Point labels try right, left, above and below the symbol; area labels sit centred on their anchor.
public enum LabelPlacer {
    /// The space kept free around each label, in points.
    static let padding = 2.0

    /// Places labels.
    ///
    /// - Parameters:
    ///   - candidates: The names to place. Only the first candidate per `objectID` is used, so give the best one first.
    ///   - viewWidth: The width of the view in points.
    ///   - viewHeight: The height of the view in points.
    ///   - measure: Returns the size of a text box for a text and a font size, in points.
    /// - Returns: The labels that found a place, in priority order.
    public static func place(
        _ candidates: [LabelCandidate], viewWidth: Double, viewHeight: Double,
        measure: (String, Double) -> (width: Double, height: Double)
    ) -> [PlacedLabel] {
        var occupied: [ScreenBounds] = candidates.compactMap { candidate in
            guard candidate.symbolRadius > 0 else { return nil }
            let r = candidate.symbolRadius
            return ScreenBounds(of: [
                ScreenPoint(x: candidate.anchor.x - r, y: candidate.anchor.y - r),
                ScreenPoint(x: candidate.anchor.x + r, y: candidate.anchor.y + r),
            ])
        }
        let ordered = candidates.sorted {
            ($1.style.priority, $0.objectID, $0.text) < ($0.style.priority, $1.objectID, $1.text)
        }
        var seen = Set<Int64>()
        var placed: [PlacedLabel] = []
        for candidate in ordered where !seen.contains(candidate.objectID) {
            let size = measure(candidate.text, candidate.fontSize)
            guard size.width > 0, size.height > 0 else { continue }
            for origin in positions(for: candidate, width: size.width, height: size.height) {
                let box = ScreenBounds(of: [
                    ScreenPoint(x: origin.x - padding, y: origin.y - padding),
                    ScreenPoint(x: origin.x + size.width + padding, y: origin.y + size.height + padding),
                ])
                guard let box, box.minX >= 0, box.minY >= 0, box.maxX <= viewWidth, box.maxY <= viewHeight,
                      !occupied.contains(where: { $0.intersects(box) })
                else { continue }
                occupied.append(box)
                seen.insert(candidate.objectID)
                placed.append(PlacedLabel(
                    text: candidate.text, origin: origin, width: size.width, height: size.height,
                    fontSize: candidate.fontSize, style: candidate.style))
                break
            }
        }
        return placed
    }

    private static func positions(for candidate: LabelCandidate, width: Double, height: Double) -> [ScreenPoint] {
        let a = candidate.anchor
        guard candidate.symbolRadius > 0 else {
            return [ScreenPoint(x: a.x - width / 2, y: a.y - height / 2)]
        }
        let gap = candidate.symbolRadius + 3
        return [
            ScreenPoint(x: a.x + gap, y: a.y - height / 2),
            ScreenPoint(x: a.x - gap - width, y: a.y - height / 2),
            ScreenPoint(x: a.x - width / 2, y: a.y - gap - height),
            ScreenPoint(x: a.x - width / 2, y: a.y + gap),
        ]
    }
}
