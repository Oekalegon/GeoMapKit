/// Douglas-Peucker on a polyline in a flat plane, without recursion (a route can have a million points).
enum RouteSimplifier {
    /// The indices to keep, ascending, always including the first and the last of the range.
    ///
    /// - Parameters:
    ///   - x: The x of every point.
    ///   - y: The y of every point.
    ///   - range: The points of one polyline.
    ///   - tolerance: The most a dropped point may be from the simplified line, in the units of x and y.
    static func keep(x: [Double], y: [Double], in range: Range<Int>, tolerance: Double) -> [Int] {
        guard range.count > 2 else { return Array(range) }
        var keep = [Bool](repeating: false, count: range.count)
        keep[0] = true
        keep[range.count - 1] = true
        var stack = [(range.lowerBound, range.upperBound - 1)]
        while let (first, last) = stack.popLast() {
            guard last - first > 1 else { continue }
            var farthest = -1
            var farthestDistance = tolerance
            for index in (first + 1)..<last {
                let distance = distanceToSegment(x[index], y[index], x[first], y[first], x[last], y[last])
                if distance > farthestDistance { farthestDistance = distance; farthest = index }
            }
            guard farthest >= 0 else { continue }
            keep[farthest - range.lowerBound] = true
            stack.append((first, farthest))
            stack.append((farthest, last))
        }
        return keep.indices.filter { keep[$0] }.map { $0 + range.lowerBound }
    }

    private static func distanceToSegment(_ px: Double, _ py: Double, _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
        let dx = bx - ax, dy = by - ay
        let squared = dx * dx + dy * dy
        guard squared > 0 else { return ((px - ax) * (px - ax) + (py - ay) * (py - ay)).squareRoot() }
        let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / squared))
        let cx = ax + t * dx, cy = ay + t * dy
        return ((px - cx) * (px - cx) + (py - cy) * (py - cy)).squareRoot()
    }
}
