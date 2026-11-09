import FeatureStore

/// In a style file the classes are keyed by the Swift case name of ``FeatureClass`` (`roadMajor`, `waterArea`, …).
/// Those names are part of the file format: renaming a case needs a format version bump or an alias, and
/// `StyleJSONTests` pins the list.
extension MapStyle: Codable {
    private enum Keys: String, CodingKey, CaseIterable { case formatVersion, name, background, attribution, labels, classes }

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
        // Style files written before `countryBorder` existed draw national borders with the boundary style, as they did
        // when those borders were still classed as boundaries; without this they would lose them.
        if classes[.countryBorder] == nil, let boundary = classes[.boundary] { classes[.countryBorder] = boundary }
        // Protected areas were `boundary` before `parkBorder` existed, and the sea part of their border has the colour of the land part.
        if classes[.parkBorder] == nil, let boundary = classes[.boundary] { classes[.parkBorder] = boundary }
        if classes[.parkBorderSea] == nil, let park = classes[.parkBorder] { classes[.parkBorderSea] = park }
        // Military land was part of `landuseUrban` before `militaryArea` existed (rule table 17); a style file from then draws it that way.
        // (A file cannot hide military land by leaving the class out: a missing class is read as an old file.)
        if classes[.militaryArea] == nil, let urban = classes[.landuseUrban] { classes[.militaryArea] = urban }
        // Glaciers, bare ground, sand and wetland were part of `landcover` before rule table 18; a style file from then draws them that way.
        for split in [FeatureClass.glacier, .bareGround, .wetland, .sand] where classes[split] == nil {
            if let cover = classes[.landcover] { classes[split] = cover }
        }
        // River names are a class of their own since rule table 20 and a style file from before has no entry for it: the name of a wide
        // river is then drawn like the name of a stream.
        if classes[.riverName] == nil, let stream = classes[.waterLine], let label = stream.label {
            classes[.riverName] = ClassStyle(label: label, visibleZoom: stream.visibleZoom, layer: stream.layer)
        }
        // Service roads were part of `roadMinor` before `roadService` existed; a style file from then draws them as streets.
        if classes[.roadService] == nil, let street = classes[.roadMinor] { classes[.roadService] = street }
        self.init(
            name: try c.decode(String.self, forKey: .name), background: try c.decode(MapColor.self, forKey: .background),
            classes: classes, attribution: try c.decodeIfPresent(AttributionDisplay.self, forKey: .attribution) ?? .full,
            labels: try c.decodeIfPresent(LabelSettings.self, forKey: .labels) ?? LabelSettings())
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(Self.jsonFormatVersion, forKey: .formatVersion)
        try c.encode(name, forKey: .name)
        try c.encode(background, forKey: .background)
        try c.encode(attribution, forKey: .attribution)
        try c.encode(labels, forKey: .labels)
        var raw = c.nestedContainer(keyedBy: StyleKey.self, forKey: .classes)
        for (featureClass, style) in classes {
            try raw.encode(style, forKey: StyleKey(stringValue: String(describing: featureClass)))
        }
    }
}
