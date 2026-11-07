extension FillStyle: Codable {
    private enum Keys: String, CodingKey, CaseIterable { case color }

    public init(from decoder: Decoder) throws {
        try decoder.requireKnownKeys(Keys.self)
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(color: try c.decode(ZoomValue<MapColor>.self, forKey: .color))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(color, forKey: .color)
    }
}
