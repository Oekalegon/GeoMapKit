extension GroundWidth: Codable {
    private enum Keys: String, CodingKey, CaseIterable { case metresPerLane, defaultLanes, maximumLanes }

    public init(from decoder: Decoder) throws {
        try decoder.requireKnownKeys(Keys.self)
        let c = try decoder.container(keyedBy: Keys.self)
        let metres = try c.decodeNumber(forKey: .metresPerLane)
        guard metres > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .metresPerLane, in: c, debugDescription: "must be greater than 0")
        }
        self.init(
            metresPerLane: metres, defaultLanes: try c.decodeNumber(forKey: .defaultLanes),
            maximumLanes: try c.decodeNumber(forKey: .maximumLanes, atLeast: 1, default: 12))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(metresPerLane, forKey: .metresPerLane)
        try c.encode(defaultLanes, forKey: .defaultLanes)
        try c.encode(maximumLanes, forKey: .maximumLanes)
    }
}
