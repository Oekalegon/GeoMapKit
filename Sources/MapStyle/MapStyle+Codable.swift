import FeatureStore

extension MapStyle: Codable {
    private enum Keys: String, CodingKey, CaseIterable { case formatVersion, name, background, attribution, classes }

    public init(from decoder: Decoder) throws {
        try decoder.requireKnownKeys(Keys.self)
        let c = try decoder.container(keyedBy: Keys.self)
        let version = try c.decode(Int.self, forKey: .formatVersion)
        guard version == Self.jsonFormatVersion else { throw MapStyleError.unsupportedVersion(version) }

        let byName = Dictionary(uniqueKeysWithValues: FeatureClass.allCases.map { (String(describing: $0), $0) })
        let raw = try c.nestedContainer(keyedBy: StyleKey.self, forKey: .classes)
        var classes: [FeatureClass: ClassStyle] = [:]
        for key in raw.allKeys.sorted(by: { $0.stringValue < $1.stringValue }) {
            guard let featureClass = byName[key.stringValue] else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: raw.codingPath + [key],
                        debugDescription: "unknown feature class '\(key.stringValue)'; known: \(byName.keys.sorted().joined(separator: ", "))"))
            }
            classes[featureClass] = try raw.decode(ClassStyle.self, forKey: key)
        }
        self.init(
            name: try c.decode(String.self, forKey: .name), background: try c.decode(MapColor.self, forKey: .background),
            classes: classes, attribution: try c.decodeIfPresent(AttributionDisplay.self, forKey: .attribution) ?? .full)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(Self.jsonFormatVersion, forKey: .formatVersion)
        try c.encode(name, forKey: .name)
        try c.encode(background, forKey: .background)
        try c.encode(attribution, forKey: .attribution)
        var raw = c.nestedContainer(keyedBy: StyleKey.self, forKey: .classes)
        for (featureClass, style) in classes {
            guard let key = StyleKey(stringValue: String(describing: featureClass)) else { continue }
            try raw.encode(style, forKey: key)
        }
    }
}
