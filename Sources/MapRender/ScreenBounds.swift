/// An axis-aligned rectangle in screen points, used to cull features that are off screen.
struct ScreenBounds {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    /// The bounds of a set of points, or `nil` if there are none.
    init?<S: Sequence>(of points: S) where S.Element == ScreenPoint {
        var iterator = points.makeIterator()
        guard let first = iterator.next() else { return nil }
        minX = first.x
        maxX = first.x
        minY = first.y
        maxY = first.y
        while let point = iterator.next() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
    }

    /// The rectangle `0...width × 0...height` grown by `margin` on every side.
    init(width: Double, height: Double, margin: Double) {
        minX = -margin
        minY = -margin
        maxX = width + margin
        maxY = height + margin
    }

    func intersects(_ other: ScreenBounds) -> Bool {
        minX <= other.maxX && maxX >= other.minX && minY <= other.maxY && maxY >= other.minY
    }
}
