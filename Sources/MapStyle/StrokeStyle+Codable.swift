extension StrokeStyle: Codable {
    private enum Keys: String, CodingKey, CaseIterable { case color, width, dash, cap, join, casing }

    public init(from decoder: Decoder) throws {
        try decoder.requireKnownKeys(Keys.self)
        let c = try decoder.container(keyedBy: Keys.self)
        let dash = try c.decodeIfPresent([Double].self, forKey: .dash) ?? []
        guard dash.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw DecodingError.dataCorruptedError(forKey: .dash, in: c, debugDescription: "dash lengths must be finite and not negative")
        }
        self.init(
            color: try c.decode(ZoomValue<MapColor>.self, forKey: .color), width: try c.decode(LineWidth.self, forKey: .width),
            dash: dash, cap: try c.decodeIfPresent(LineCap.self, forKey: .cap) ?? .round,
            join: try c.decodeIfPresent(LineJoin.self, forKey: .join) ?? .round,
            casing: try c.decodeIfPresent(Casing.self, forKey: .casing))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(color, forKey: .color)
        try c.encode(width, forKey: .width)
        if !dash.isEmpty { try c.encode(dash, forKey: .dash) }
        try c.encode(cap, forKey: .cap)
        try c.encode(join, forKey: .join)
        try c.encodeIfPresent(casing, forKey: .casing)
    }
}

extension StrokeStyle.Casing: Codable {
    private enum Keys: String, CodingKey, CaseIterable { case color, extraPoints }

    public init(from decoder: Decoder) throws {
        try decoder.requireKnownKeys(Keys.self)
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(
            color: try c.decode(ZoomValue<MapColor>.self, forKey: .color), extraPoints: try c.decodeZoomNumber(forKey: .extraPoints))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(color, forKey: .color)
        try c.encode(extraPoints, forKey: .extraPoints)
    }
}
