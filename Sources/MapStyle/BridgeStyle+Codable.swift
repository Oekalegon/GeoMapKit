extension BridgeStyle: Codable {
    private enum Keys: String, CodingKey, CaseIterable { case casing }

    public init(from decoder: Decoder) throws {
        try decoder.requireKnownKeys(Keys.self)
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(casing: try c.decode(StrokeStyle.Casing.self, forKey: .casing))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(casing, forKey: .casing)
    }
}
