import FeatureStore
import Foundation

/// Clips a polyline to a cell.
///
/// Intersections are computed in Web Mercator on the original segment, with the
/// segment's endpoints in a fixed order, so the two cells on either side of a border
/// compute the same border point (apart from a rare rounding tie of one unit,
/// 1e-7 degrees). A line that leaves a cell and returns gives several pieces.
///
/// The cell is closed. A piece that is a single point (the line only touches the
/// cell) is dropped, and a piece lying along the east or south border is left to the
/// neighbouring cell, which owns it.
enum LineClipper {
    private enum Boundary { case west, east, south, north }

    private struct SegmentClip {
        var start: PackedPoint
        var end: PackedPoint
        var startIsOriginal: Bool
        var endIsOriginal: Bool
    }

    /// A line with consecutive duplicates removed and the distance along it to every vertex,
    /// computed once so that clipping it to many cells does not repeat that work.
    struct PreparedLine {
        let points: [PackedPoint]
        /// Metres from the start to each vertex.
        let cumulative: [Double]

        init(_ line: [PackedPoint]) {
            var points: [PackedPoint] = []
            points.reserveCapacity(line.count)
            for point in line where point != points.last { points.append(point) }
            var cumulative = [Double](repeating: 0, count: points.count)
            if points.count > 1 {
                for index in 1..<points.count {
                    cumulative[index] = cumulative[index - 1] + Geodesy.distance(points[index - 1], points[index])
                }
            }
            self.points = points
            self.cumulative = cumulative
        }
    }

    /// Clips a line to a cell.
    ///
    /// - Parameters:
    ///   - line: The vertices in order. Consecutive duplicates are ignored.
    ///   - rect: The cell.
    /// - Returns: The pieces inside the cell in line order, each with its flags and the offset along the line of its first vertex.
    static func clip(_ line: [PackedPoint], to rect: CellRect) -> [ClippedLine] {
        clip(PreparedLine(line), to: rect)
    }

    /// Clips a prepared line to a cell; see ``clip(_:to:)``.
    static func clip(_ prepared: PreparedLine, to rect: CellRect) -> [ClippedLine] {
        let points = prepared.points
        let cumulative = prepared.cumulative
        guard points.count >= 2 else { return [] }

        var pieces: [ClippedLine] = []
        var current: ClippedLine?

        func finish(endsAtLineEnd: Bool) {
            guard var piece = current else { return }
            piece.continuesAfter = !endsAtLineEnd
            current = nil
            if isKept(piece, rect: rect) { pieces.append(piece) }
        }

        for index in 0..<(points.count - 1) {
            let a = points[index], b = points[index + 1]
            guard let clip = clipSegment(a, b, rect: rect) else {
                finish(endsAtLineEnd: false)
                continue
            }
            if current != nil, current?.points.last == clip.start {
                current?.points.append(clip.end)
            } else {
                finish(endsAtLineEnd: false)
                let offset = cumulative[index] + (clip.startIsOriginal ? 0 : Geodesy.distance(a, clip.start))
                current = ClippedLine(
                    points: [clip.start, clip.end], continuesBefore: !(index == 0 && clip.startIsOriginal),
                    continuesAfter: false, offsetCentimetres: centimetres(offset))
            }
            if !clip.endIsOriginal { finish(endsAtLineEnd: false) }
        }
        finish(endsAtLineEnd: current?.points.last == points.last)
        return pieces
    }

    // MARK: Segments

    private static func clipSegment(_ a: PackedPoint, _ b: PackedPoint, rect: CellRect) -> SegmentClip? {
        // Most segments of a long line are far from the cell; reject them with integer compares before any projection.
        if (a.longitude < rect.west && b.longitude < rect.west) || (a.longitude > rect.east && b.longitude > rect.east)
            || (a.latitude < rect.south && b.latitude < rect.south) || (a.latitude > rect.north && b.latitude > rect.north)
        { return nil }
        let swapped = (b.longitude, b.latitude) < (a.longitude, a.latitude)
        let p = swapped ? b : a, q = swapped ? a : b
        let py = Mercator.y(latitude: Double(p.latitude)), qy = Mercator.y(latitude: Double(q.latitude))

        var tEnter = 0.0, tExit = 1.0
        var enter: Boundary?, exit: Boundary?
        for boundary in [Boundary.west, .east, .south, .north] {
            let pOut = isOutside(p, boundary, rect), qOut = isOutside(q, boundary, rect)
            if pOut && qOut { return nil }
            guard pOut != qOut else { continue }
            let t = crossing(boundary, p: p, q: q, py: py, qy: qy, rect: rect)
            if pOut {
                if t > tEnter { tEnter = t; enter = boundary }
            } else if t < tExit {
                tExit = t
                exit = boundary
            }
        }
        guard tEnter < tExit else { return nil }
        let first = enter.map { point(on: $0, p: p, q: q, py: py, qy: qy, t: tEnter, rect: rect) } ?? p
        let last = exit.map { point(on: $0, p: p, q: q, py: py, qy: qy, t: tExit, rect: rect) } ?? q
        guard first != last else { return nil }
        if swapped {
            return SegmentClip(start: last, end: first, startIsOriginal: exit == nil, endIsOriginal: enter == nil)
        }
        return SegmentClip(start: first, end: last, startIsOriginal: enter == nil, endIsOriginal: exit == nil)
    }

    private static func isOutside(_ point: PackedPoint, _ boundary: Boundary, _ rect: CellRect) -> Bool {
        switch boundary {
        case .west: point.longitude < rect.west
        case .east: point.longitude > rect.east
        case .south: point.latitude < rect.south
        case .north: point.latitude > rect.north
        }
    }

    private static func crossing(
        _ boundary: Boundary, p: PackedPoint, q: PackedPoint, py: Double, qy: Double, rect: CellRect
    ) -> Double {
        switch boundary {
        case .west: (Double(rect.west) - Double(p.longitude)) / (Double(q.longitude) - Double(p.longitude))
        case .east: (Double(rect.east) - Double(p.longitude)) / (Double(q.longitude) - Double(p.longitude))
        case .south: (rect.southY - py) / (qy - py)
        case .north: (rect.northY - py) / (qy - py)
        }
    }

    private static func point(
        on boundary: Boundary, p: PackedPoint, q: PackedPoint, py: Double, qy: Double, t: Double, rect: CellRect
    ) -> PackedPoint {
        switch boundary {
        case .west, .east:
            let longitude = boundary == .west ? rect.west : rect.east
            let latitude = Mercator.latitude(y: py + t * (qy - py)).rounded()
            return PackedPoint(longitude: longitude, latitude: clamp(latitude, rect.south, rect.north))
        case .south, .north:
            let latitude = boundary == .south ? rect.south : rect.north
            let longitude = (Double(p.longitude) + t * (Double(q.longitude) - Double(p.longitude))).rounded()
            return PackedPoint(longitude: clamp(longitude, rect.west, rect.east), latitude: latitude)
        }
    }

    private static func clamp(_ value: Double, _ low: Int32, _ high: Int32) -> Int32 {
        Int32(max(Double(low), min(Double(high), value)))
    }

    // MARK: Pieces

    private static func isKept(_ piece: ClippedLine, rect: CellRect) -> Bool {
        guard piece.points.count >= 2, Set(piece.points).count >= 2 else { return false }
        if !rect.isLastColumn, piece.points.allSatisfy({ $0.longitude == rect.east }) { return false }
        if !rect.isLastRow, piece.points.allSatisfy({ $0.latitude == rect.south }) { return false }
        return true
    }

    private static func centimetres(_ metres: Double) -> UInt32 {
        UInt32(max(0, min(Double(UInt32.max), (metres * 100).rounded())))
    }
}
