/// A style value that depends on the zoom level.
///
/// A value is a list of stops. Between two stops the value is interpolated
/// linearly in the zoom level; below the first stop and above the last stop it
/// stays constant. Zoom is fractional, so a pinch gesture changes values smoothly.
///
/// ```swift
/// let width = ZoomValue((12, 1.0), (16, 3.0))   // 1 pt at zoom 12 and lower, 3 pt at zoom 16 and higher
/// width.value(atZoom: 14)                         // 2.0
/// ```
public struct ZoomValue<Value: ZoomInterpolatable>: Sendable {
    /// One zoom level and the value that applies there.
    public struct Stop: Sendable {
        /// The zoom level of this stop.
        public var zoom: Double
        /// The value at ``zoom``.
        public var value: Value

        /// Creates a stop.
        public init(zoom: Double, value: Value) {
            self.zoom = zoom
            self.value = value
        }
    }

    /// The stops, sorted by ascending zoom. Never empty.
    public let stops: [Stop]

    /// Creates a value that is the same at every zoom level.
    public init(constant value: Value) {
        stops = [Stop(zoom: 0, value: value)]
    }

    /// Creates a value from stops. The stops may be given in any order.
    ///
    /// Stop zooms must be finite numbers. When two stops share a zoom level, the later one in the argument list wins.
    public init(_ first: (zoom: Double, value: Value), _ rest: (zoom: Double, value: Value)...) {
        let all = ([first] + rest).map { Stop(zoom: $0.zoom, value: $0.value) }
        // Walk the stops in zoom order; for equal zooms keep the one given last.
        var sorted: [Stop] = []
        for stop in all.enumerated().sorted(by: { ($0.element.zoom, $0.offset) < ($1.element.zoom, $1.offset) }).map(\.element) {
            if let last = sorted.last, last.zoom == stop.zoom { sorted.removeLast() }
            sorted.append(stop)
        }
        stops = sorted
    }

    /// The value at a zoom level.
    ///
    /// A non-finite zoom (NaN) gives the first stop's value.
    public func value(atZoom zoom: Double) -> Value {
        let first = stops[0]
        let last = stops[stops.count - 1]
        if !(zoom > first.zoom) { return first.value }
        if zoom >= last.zoom { return last.value }
        // Binary search for the first stop above `zoom`.
        var low = 0
        var high = stops.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if stops[mid].zoom <= zoom { low = mid } else { high = mid }
        }
        let a = stops[low]
        let b = stops[high]
        return a.value.interpolated(to: b.value, fraction: (zoom - a.zoom) / (b.zoom - a.zoom))
    }
}

extension ZoomValue.Stop: Equatable where Value: Equatable {}
extension ZoomValue: Equatable where Value: Equatable {}
