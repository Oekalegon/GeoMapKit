import FeatureStore
import Foundation

extension LabelPlacer {
    /// The most a stretch of line may turn, in radians, for text to run along it.
    static let maximumTurn = 40.0 * Double.pi / 180
    /// The nearest two labels with the same text may be, in points.
    static let sameTextDistance = 200.0
    /// The most places tried for the name along one run of line.
    private static let maximumSlots = 8
    /// The distance, in points, from the middle of the line to the edge of the text box beside it: the letters nearly touch the line and may overlap the wide band of a national border.
    private static let sideGap = 1.0

    /// Places the name along a line, as many times as fits, and returns the labels.
    ///
    /// The line is cut to the parts that lie in the view. On each part the name is tried in the middle first, then at steps
    /// along the part, so a name that does not fit at the bend of a road still finds a straight stretch. Long parts get the
    /// name again every 300 points or four name lengths, whichever is more. A line with names on both sides gets them both
    /// at the same place, or not at all.
    static func placeAlongLine(
        _ candidate: LineLabelCandidate, parts: [LinePart], viewWidth: Double, viewHeight: Double, padding: Double,
        remaining: Int?, occupied: inout [ScreenBounds], state: inout LineLabelState
    ) -> [PlacedLabel] {
        let widest = parts.map(\.size.width).max() ?? 0
        guard widest > 0 else { return [] }
        let view = ScreenBounds(width: viewWidth, height: viewHeight, margin: 0)
        var placed: [PlacedLabel] = []
        for path in LabelPath.runs(of: candidate.points, in: view) where path.length >= widest + 2 * padding {
            let spacing = max(4 * widest, 300)
            // The middle, then every `spacing` to either side, as far as the name fits on the part.
            let centres: [Double] = (0..<maximumSlots).compactMap { index in
                let centre = path.length / 2 + Double((index + 1) / 2) * spacing * (index % 2 == 1 ? 1 : -1)
                return centre - widest / 2 >= 0 && centre + widest / 2 <= path.length ? centre : nil
            }
            for centre in centres {
                if let remaining, placed.count + parts.count > remaining { return placed }
                let shifts: [Double] = [0, 1, -1, 2, -2, 3, -3].map { $0 * widest / 3 }
                for shift in shifts {
                    var group: [(placed: PlacedLabel, boxes: [ScreenBounds], centre: ScreenPoint)] = []
                    for part in parts {
                        let start = centre + shift - part.size.width / 2
                        guard start >= 0, start + part.size.width <= path.length,
                            let label = label(
                                candidate, part: part, along: path, from: start, view: view, padding: padding,
                                occupied: occupied, state: state)
                        else { break }
                        group.append(label)
                    }
                    guard group.count == parts.count else { continue }
                    for (part, label) in zip(parts, group) {
                        occupied += label.boxes
                        state.centres[part.text, default: []].append(label.centre)
                        placed.append(label.placed)
                    }
                    break
                }
            }
        }
        return placed
    }

    /// The parts of a line label: one name on the line, or for a label beside the line the names of its sides, each measured.
    /// The text is not split when the label goes on the line.
    static func lineParts(
        of candidate: LineLabelCandidate, characterOffsets: ((String, Double) -> [Double])?,
        measure: (String, Double) -> (width: Double, height: Double)
    ) -> [LinePart] {
        var named: [(String, LinePart.Side)]
        switch candidate.style.placement {
        case .onLine: named = [(candidate.text, .on)]
        case .besideLine:
            if let sided = SidedName(text: candidate.text) {
                named = [(sided.left, .left), (sided.right, .right)]
            } else {
                named = [(candidate.text, .above)]
            }
        }
        return named.compactMap { text, side in
            let characters = Array(text)
            let size = measure(text, candidate.fontSize)
            guard !characters.isEmpty, size.width > 0, size.height > 0 else { return nil }
            let starts = glyphStarts(
                characters.count, width: size.width, offsets: characterOffsets?(text, candidate.fontSize))
            return LinePart(text: text, characters: characters, starts: starts, size: size, side: side)
        }
    }

    /// Where each character starts along the text, plus the total as the last value; evenly spaced if the measurement
    /// is missing or does not fit the text.
    private static func glyphStarts(_ count: Int, width: Double, offsets: [Double]?) -> [Double] {
        if let offsets, offsets.count == count + 1, offsets.allSatisfy(\.isFinite), zip(offsets, offsets.dropFirst()).allSatisfy({ $0 <= $1 }) {
            return offsets
        }
        return (0...count).map { width * Double($0) / Double(count) }
    }

    /// Lays the letters along the path from a distance, or returns `nil` when the stretch is too curved, leaves the view,
    /// or meets something else.
    private static func label(
        _ candidate: LineLabelCandidate, part: LinePart, along path: LabelPath, from start: Double, view: ScreenBounds,
        padding: Double, occupied: [ScreenBounds], state: LineLabelState
    ) -> (placed: PlacedLabel, boxes: [ScreenBounds], centre: ScreenPoint)? {
        let characters = part.characters, starts = part.starts, size = part.size
        let end = start + size.width
        guard path.isGentle(from: start, to: end, maximumTurn: maximumTurn) else { return nil }
        let from = path.position(at: start), to = path.position(at: end)
        let middle = path.position(at: (start + end) / 2)
        if state.centres[part.text]?.contains(where: { hypot($0.x - middle.x, $0.y - middle.y) < sameTextDistance }) == true {
            return nil
        }
        // Text reads from left to right, or upwards on a vertical line, never upside down.
        let dx = to.x - from.x, dy = to.y - from.y
        let reversed = dx < -1e-9 || (abs(dx) <= 1e-9 && dy > 0)
        // How far the text sits from the line, towards the top of the letters (away from it if negative). Text on the left
        // of the line is above it when it reads in the direction of the line, and below it when it reads against it.
        let gap = candidate.fontSize / 2 + sideGap
        let lift: Double
        switch part.side {
        case .on: lift = 0
        case .above: lift = gap
        case .left: lift = reversed ? -gap : gap
        case .right: lift = reversed ? gap : -gap
        }

        var glyphs: [PlacedGlyph] = []
        var boxes: [ScreenBounds] = []
        for (index, character) in characters.enumerated() {
            let width = starts[index + 1] - starts[index]
            let along = (starts[index] + starts[index + 1]) / 2
            let distance = reversed ? end - along : start + along
            let reach = max(width / 2, candidate.fontSize * 0.4)
            let before = path.position(at: distance - reach), after = path.position(at: distance + reach)
            var angle = atan2(after.y - before.y, after.x - before.x)
            if reversed { angle += .pi }
            if angle > .pi { angle -= 2 * .pi }
            let onLine = path.position(at: distance)
            // The top of the letters points to (sin, -cos) of the angle.
            let position = ScreenPoint(x: onLine.x + sin(angle) * lift, y: onLine.y - cos(angle) * lift)
            let half = max(size.height, width) / 2
            guard let inView = ScreenBounds(of: [
                ScreenPoint(x: position.x - half, y: position.y - half), ScreenPoint(x: position.x + half, y: position.y + half),
            ]), inView.minX >= view.minX, inView.minY >= view.minY, inView.maxX <= view.maxX, inView.maxY <= view.maxY
            else { return nil }
            let box = ScreenBounds(of: [
                ScreenPoint(x: inView.minX - padding, y: inView.minY - padding),
                ScreenPoint(x: inView.maxX + padding, y: inView.maxY + padding),
            ])
            guard let box else { return nil }
            boxes.append(box)
            glyphs.append(PlacedGlyph(text: String(character), position: position, angle: angle, width: width))
        }
        guard let all = ScreenBounds(of: boxes.flatMap { [ScreenPoint(x: $0.minX, y: $0.minY), ScreenPoint(x: $0.maxX, y: $0.maxY)] })
        else { return nil }
        for other in occupied where other.intersects(all) {
            if boxes.contains(where: { $0.intersects(other) }) { return nil }
        }
        let placed = PlacedLabel(
            text: part.text, origin: ScreenPoint(x: all.minX + padding, y: all.minY + padding), width: size.width,
            height: size.height, fontSize: candidate.fontSize, style: candidate.style, glyphs: glyphs)
        return (placed, boxes, middle)
    }
}
