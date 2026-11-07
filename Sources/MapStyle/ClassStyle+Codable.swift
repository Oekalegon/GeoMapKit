extension ClassStyle: Codable {
    private enum Keys: String, CodingKey, CaseIterable { case fill, stroke, point, label, visibleZoom, layer, casingLayer }

    public init(from decoder: Decoder) throws {
        try decoder.requireKnownKeys(Keys.self)
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(
            fill: try c.decodeIfPresent(FillStyle.self, forKey: .fill), stroke: try c.decodeIfPresent(StrokeStyle.self, forKey: .stroke),
            point: try c.decodeIfPresent(PointStyle.self, forKey: .point), label: try c.decodeIfPresent(LabelStyle.self, forKey: .label),
            visibleZoom: try c.decodeZoomRange(forKey: .visibleZoom, default: 0...24), layer: try c.decode(Int.self, forKey: .layer),
            casingLayer: try c.decodeIfPresent(Int.self, forKey: .casingLayer))
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
    }
}
