extension TagCondition: Codable {
    private enum Keys: String, CodingKey, CaseIterable { case key, values }

    public init(from decoder: Decoder) throws {
        try decoder.requireKnownKeys(Keys.self)
        let c = try decoder.container(keyedBy: Keys.self)
        let key = try c.decode(String.self, forKey: .key)
        guard !key.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .key, in: c, debugDescription: "expects the key of an OSM tag, for example \"gauge\"")
        }
        self.init(key: key, values: try c.decodeIfPresent([String].self, forKey: .values) ?? [])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(key, forKey: .key)
        if !values.isEmpty { try c.encode(values, forKey: .values) }
    }
}

extension StyleVariant: Codable {
    private enum Keys: String, CodingKey, CaseIterable {
        case name, subclasses, tags, fill, stroke, point, label, visibleZoom, layer, casingLayer, bridge, tunnel
    }

    public init(from decoder: Decoder) throws {
        try decoder.requireKnownKeys(Keys.self)
        let c = try decoder.container(keyedBy: Keys.self)
        var range: ClosedRange<Double>?
        if c.contains(.visibleZoom) {
            let bounds = try c.decode([Double].self, forKey: .visibleZoom)
            guard bounds.count == 2, bounds.allSatisfy(\.isFinite), bounds[0] <= bounds[1] else {
                throw DecodingError.dataCorruptedError(
                    forKey: .visibleZoom, in: c, debugDescription: "expects [lowest, highest] zoom, for example [12, 24]")
            }
            range = bounds[0]...bounds[1]
        }
        let layer = try c.decodeIfPresent(Int.self, forKey: .layer)
        let casingLayer = try c.decodeIfPresent(Int.self, forKey: .casingLayer)
        for (value, key) in [(layer, Keys.layer), (casingLayer, Keys.casingLayer)] {
            if let value, !(0...99).contains(value) {
                throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "a layer must be between 0 and 99, not \(value)")
            }
        }
        self.init(
            name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
            subclasses: try c.decodeIfPresent([String].self, forKey: .subclasses) ?? [],
            tags: try c.decodeIfPresent([TagCondition].self, forKey: .tags) ?? [],
            fill: try c.decodeIfPresent(FillStyle.self, forKey: .fill), stroke: try c.decodeIfPresent(StrokeStyle.self, forKey: .stroke),
            point: try c.decodeIfPresent(PointStyle.self, forKey: .point), label: try c.decodeIfPresent(LabelStyle.self, forKey: .label),
            visibleZoom: range, layer: layer, casingLayer: casingLayer,
            bridge: try c.decodeIfPresent(BridgeStyle.self, forKey: .bridge), tunnel: try c.decodeIfPresent(TunnelStyle.self, forKey: .tunnel))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        if !name.isEmpty { try c.encode(name, forKey: .name) }
        if !subclasses.isEmpty { try c.encode(subclasses, forKey: .subclasses) }
        if !tags.isEmpty { try c.encode(tags, forKey: .tags) }
        try c.encodeIfPresent(fill, forKey: .fill)
        try c.encodeIfPresent(stroke, forKey: .stroke)
        try c.encodeIfPresent(point, forKey: .point)
        try c.encodeIfPresent(label, forKey: .label)
        if let visibleZoom { try c.encode([visibleZoom.lowerBound, visibleZoom.upperBound], forKey: .visibleZoom) }
        try c.encodeIfPresent(layer, forKey: .layer)
        try c.encodeIfPresent(casingLayer, forKey: .casingLayer)
        try c.encodeIfPresent(bridge, forKey: .bridge)
        try c.encodeIfPresent(tunnel, forKey: .tunnel)
    }
}
