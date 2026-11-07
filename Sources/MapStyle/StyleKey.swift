/// A coding key that accepts any name, used to find keys that a style file has but the format does not know.
struct StyleKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension Decoder {
    /// Throws if the object has a key that is not in `keys`.
    ///
    /// `Codable` ignores unknown keys by default, which would let a typo such as `"visibleZom"` fall back to a
    /// default silently. Style files are written by hand, so they fail loudly instead.
    func requireKnownKeys<K: CodingKey & CaseIterable>(_ keys: K.Type) throws {
        let known = Set(K.allCases.map(\.stringValue))
        let container = try self.container(keyedBy: StyleKey.self)
        for key in container.allKeys.sorted(by: { $0.stringValue < $1.stringValue }) where !known.contains(key.stringValue) {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: codingPath + [key],
                    debugDescription: "unknown key '\(key.stringValue)'; known keys: \(known.sorted().joined(separator: ", "))"))
        }
    }
}

extension KeyedDecodingContainer {
    /// Decodes a finite number that is at least `minimum`.
    func decodeNumber(forKey key: Key, atLeast minimum: Double = 0) throws -> Double {
        let value = try decode(Double.self, forKey: key)
        try Self.check(value, atLeast: minimum, path: codingPath + [key])
        return value
    }

    /// Decodes a finite number that is at least `minimum`, or returns `defaultValue` if the key is absent.
    func decodeNumber(forKey key: Key, atLeast minimum: Double = 0, default defaultValue: Double) throws -> Double {
        guard contains(key) else { return defaultValue }
        return try decodeNumber(forKey: key, atLeast: minimum)
    }

    /// Decodes a zoom-dependent number whose every stop is finite and at least `minimum`.
    func decodeZoomNumber(forKey key: Key, atLeast minimum: Double = 0) throws -> ZoomValue<Double> {
        let value = try decode(ZoomValue<Double>.self, forKey: key)
        for stop in value.stops { try Self.check(stop.value, atLeast: minimum, path: codingPath + [key]) }
        return value
    }

    private static func check(_ value: Double, atLeast minimum: Double, path: [CodingKey]) throws {
        guard value.isFinite, value >= minimum else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: path, debugDescription: "must be a number of at least \(minimum), not \(value)"))
        }
    }
}
