extension TunnelStyle: Codable {
    private enum Keys: String, CodingKey, CaseIterable { case opacity, dash }

    public init(from decoder: Decoder) throws {
        try decoder.requireKnownKeys(Keys.self)
        let c = try decoder.container(keyedBy: Keys.self)
        let opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.5
        guard opacity.isFinite, (0...1).contains(opacity) else {
            throw DecodingError.dataCorruptedError(forKey: .opacity, in: c, debugDescription: "opacity must be between 0 and 1")
        }
        let dash = try c.decodeIfPresent([Double].self, forKey: .dash) ?? []
        guard dash.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw DecodingError.dataCorruptedError(forKey: .dash, in: c, debugDescription: "dash lengths must be finite and not negative")
        }
        self.init(opacity: opacity, dash: dash)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(opacity, forKey: .opacity)
        if !dash.isEmpty { try c.encode(dash, forKey: .dash) }
    }
}
