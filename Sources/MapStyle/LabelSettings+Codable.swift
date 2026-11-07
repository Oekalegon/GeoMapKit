extension LabelSettings: Codable {
    private enum Keys: String, CodingKey, CaseIterable { case padding, maximumCount }

    public init(from decoder: Decoder) throws {
        try decoder.requireKnownKeys(Keys.self)
        let c = try decoder.container(keyedBy: Keys.self)
        var count: Int?
        if c.contains(.maximumCount) {
            let value = try c.decode(Int.self, forKey: .maximumCount)
            guard value >= 0 else {
                throw DecodingError.dataCorruptedError(forKey: .maximumCount, in: c, debugDescription: "must not be negative")
            }
            count = value
        }
        self.init(padding: try c.decodeNumber(forKey: .padding, default: Self.defaultPadding), maximumCount: count)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(padding, forKey: .padding)
        try c.encodeIfPresent(maximumCount, forKey: .maximumCount)
    }
}
