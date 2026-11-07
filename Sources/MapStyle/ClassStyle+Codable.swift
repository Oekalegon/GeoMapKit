extension ClassStyle: Codable {
    private enum Keys: String, CodingKey, CaseIterable { case fill, stroke, point, label, visibleZoom, layer, casingLayer, bridge, tunnel }

    public init(from decoder: Decoder) throws {
        try decoder.requireKnownKeys(Keys.self)
        let c = try decoder.container(keyedBy: Keys.self)
        var range: ClosedRange<Double> = 0...24
        if c.contains(.visibleZoom) {
            let bounds = try c.decode([Double].self, forKey: .visibleZoom)
            guard bounds.count == 2, bounds.allSatisfy(\.isFinite), bounds[0] <= bounds[1] else {
                throw DecodingError.dataCorruptedError(
                    forKey: .visibleZoom, in: c, debugDescription: "expects [lowest, highest] zoom, for example [12, 24]")
            }
            range = bounds[0]...bounds[1]
        }
        self.init(
            fill: try c.decodeIfPresent(FillStyle.self, forKey: .fill), stroke: try c.decodeIfPresent(StrokeStyle.self, forKey: .stroke),
            point: try c.decodeIfPresent(PointStyle.self, forKey: .point), label: try c.decodeIfPresent(LabelStyle.self, forKey: .label),
            visibleZoom: range, layer: try c.decode(Int.self, forKey: .layer),
            casingLayer: try c.decodeIfPresent(Int.self, forKey: .casingLayer),
            bridge: try c.decodeIfPresent(BridgeStyle.self, forKey: .bridge),
            tunnel: try c.decodeIfPresent(TunnelStyle.self, forKey: .tunnel))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encodeIfPresent(fill, forKey: .fill)
        try c.encodeIfPresent(stroke, forKey: .stroke)
        try c.encodeIfPresent(point, forKey: .point)
        try c.encodeIfPresent(label, forKey: .label)
        try c.encode([visibleZoom.lowerBound, visibleZoom.upperBound], forKey: .visibleZoom)
        try c.encode(layer, forKey: .layer)
        try c.encodeIfPresent(casingLayer, forKey: .casingLayer)
        try c.encodeIfPresent(bridge, forKey: .bridge)
        try c.encodeIfPresent(tunnel, forKey: .tunnel)
    }
}
