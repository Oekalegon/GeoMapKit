import FeatureStore

/// Whether a point lies in the sea, from the rings of the sea polygon.
///
/// The rings are those of ``SeaBuilder`` (the sea with the islands as holes, filled by the even-odd rule). A point is tested with
/// a ray to the east, against the edges whose latitude range holds the point's latitude; the edges are sorted into bands of
/// latitude once, so a test looks at a few hundred edges, not at the millions of a long coast.
struct SeaLookup {
    private static let bandCount = 4096
    private var x0: [Int32] = [], y0: [Int32] = [], x1: [Int32] = [], y1: [Int32] = []
    private var bands: [[Int32]]
    private let minimumLatitude: Double
    private let bandHeight: Double

    /// Creates the lookup.
    ///
    /// - Parameter rings: Closed rings of the sea and its islands.
    init(rings: [[PackedPoint]]) {
        var low = Int32.max, high = Int32.min
        for ring in rings { for point in ring { low = min(low, point.latitude); high = max(high, point.latitude) } }
        minimumLatitude = Double(low)
        bandHeight = max(1, (Double(high) - Double(low)) / Double(Self.bandCount) + 1)
        bands = Array(repeating: [], count: Self.bandCount)
        for ring in rings where ring.count >= 2 {
            for index in 0..<ring.count {
                let a = ring[index], b = ring[(index + 1) % ring.count]
                guard a.latitude != b.latitude else { continue }
                let edge = Int32(x0.count)
                x0.append(a.longitude); y0.append(a.latitude); x1.append(b.longitude); y1.append(b.latitude)
                let first = band(of: Double(min(a.latitude, b.latitude))), last = band(of: Double(max(a.latitude, b.latitude)))
                for band in first...last { bands[band].append(edge) }
            }
        }
    }

    /// Whether a point lies in the sea.
    func contains(_ point: PackedPoint) -> Bool {
        let y = Double(point.latitude), x = Double(point.longitude)
        guard !x0.isEmpty, y >= minimumLatitude else { return false }
        let index = band(of: y)
        guard index < bands.count else { return false }
        var inside = false
        for edge in bands[index] {
            let ax = Double(x0[Int(edge)]), ay = Double(y0[Int(edge)]), bx = Double(x1[Int(edge)]), by = Double(y1[Int(edge)])
            if (ay > y) != (by > y), x < (bx - ax) * (y - ay) / (by - ay) + ax { inside.toggle() }
        }
        return inside
    }

    private func band(of latitude: Double) -> Int {
        min(Self.bandCount - 1, max(0, Int((latitude - minimumLatitude) / bandHeight)))
    }
}
