extension LineWidth: Codable {
    private enum Keys: String, CodingKey, CaseIterable { case points, ground }

    public init(from decoder: Decoder) throws {
        try decoder.requireKnownKeys(Keys.self)
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(
            points: try c.decodeZoomNumber(forKey: .points), ground: try c.decodeIfPresent(GroundWidth.self, forKey: .ground))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(points, forKey: .points)
        try c.encodeIfPresent(ground, forKey: .ground)
    }
}
