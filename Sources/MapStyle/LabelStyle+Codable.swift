extension LabelStyle: Codable {
    private enum Keys: String, CodingKey, CaseIterable { case size, color, haloColor, haloWidth, priority, visibleZoom, placement, minimumArea, thinningRadius, populationScale }

    public init(from decoder: Decoder) throws {
        try decoder.requireKnownKeys(Keys.self)
        let c = try decoder.container(keyedBy: Keys.self)
        var range: ClosedRange<Double> = 0...24
        if c.contains(.visibleZoom) {
            let bounds = try c.decode([Double].self, forKey: .visibleZoom)
            guard bounds.count == 2, bounds.allSatisfy(\.isFinite), bounds[0] <= bounds[1] else {
                throw DecodingError.dataCorruptedError(
                    forKey: .visibleZoom, in: c, debugDescription: "expects [lowest, highest] zoom, for example [14, 24]")
            }
            range = bounds[0]...bounds[1]
        }
        self.init(
            size: try c.decodeZoomNumber(forKey: .size), color: try c.decode(MapColor.self, forKey: .color),
            haloColor: try c.decodeIfPresent(MapColor.self, forKey: .haloColor) ?? .white,
            haloWidth: try c.decodeNumber(forKey: .haloWidth, default: 2),
            priority: try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0, visibleZoom: range,
            placement: try c.decodeIfPresent(LabelPlacement.self, forKey: .placement) ?? .onLine,
            minimumArea: try c.decodeNumber(forKey: .minimumArea, default: 0),
            thinningRadius: c.contains(.thinningRadius) ? try c.decodeZoomNumber(forKey: .thinningRadius) : ZoomValue(constant: 0),
            populationScale: try c.decodeIfPresent(PopulationScale.self, forKey: .populationScale))
        guard minimumArea >= 0, minimumArea.isFinite else {
            throw DecodingError.dataCorruptedError(forKey: .minimumArea, in: c, debugDescription: "expects an area of 0 or more square points")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(size, forKey: .size)
        try c.encode(color, forKey: .color)
        try c.encode(haloColor, forKey: .haloColor)
        try c.encode(haloWidth, forKey: .haloWidth)
        try c.encode(priority, forKey: .priority)
        try c.encode([visibleZoom.lowerBound, visibleZoom.upperBound], forKey: .visibleZoom)
        // Only written when it is not the default, so that style files without besideLine labels stay as they were and
        // older readers (which refuse unknown keys) can still read them.
        if placement != .onLine { try c.encode(placement, forKey: .placement) }
        if minimumArea > 0 { try c.encode(minimumArea, forKey: .minimumArea) }
        if let populationScale { try c.encode(populationScale, forKey: .populationScale) }
        if thinningRadius != ZoomValue(constant: 0) { try c.encode(thinningRadius, forKey: .thinningRadius) }
    }
}
