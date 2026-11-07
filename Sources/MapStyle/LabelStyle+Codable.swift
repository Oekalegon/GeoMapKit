extension LabelStyle: Codable {
    private enum Keys: String, CodingKey, CaseIterable { case size, color, haloColor, haloWidth, priority, visibleZoom }

    public init(from decoder: Decoder) throws {
        try decoder.requireKnownKeys(Keys.self)
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(
            size: try c.decodeZoomNumber(forKey: .size), color: try c.decode(MapColor.self, forKey: .color),
            haloColor: try c.decodeIfPresent(MapColor.self, forKey: .haloColor) ?? .white,
            haloWidth: try c.decodeNumber(forKey: .haloWidth, default: 2),
            priority: try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0, visibleZoom: try c.decodeZoomRange(forKey: .visibleZoom, default: 0...24))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(size, forKey: .size)
        try c.encode(color, forKey: .color)
        try c.encode(haloColor, forKey: .haloColor)
        try c.encode(haloWidth, forKey: .haloWidth)
        try c.encode(priority, forKey: .priority)
        try c.encode([visibleZoom.lowerBound, visibleZoom.upperBound], forKey: .visibleZoom)
    }
}
