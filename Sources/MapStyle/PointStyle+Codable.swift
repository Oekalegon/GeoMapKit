extension PointStyle: Codable {
    private enum Keys: String, CodingKey, CaseIterable { case radius, color, outlineColor, outlineWidth }

    public init(from decoder: Decoder) throws {
        try decoder.requireKnownKeys(Keys.self)
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(
            radius: try c.decodeZoomNumber(forKey: .radius), color: try c.decode(ZoomValue<MapColor>.self, forKey: .color),
            outlineColor: try c.decodeIfPresent(MapColor.self, forKey: .outlineColor) ?? .white,
            outlineWidth: try c.decodeNumber(forKey: .outlineWidth, default: 1))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(radius, forKey: .radius)
        try c.encode(color, forKey: .color)
        try c.encode(outlineColor, forKey: .outlineColor)
        try c.encode(outlineWidth, forKey: .outlineWidth)
    }
}
