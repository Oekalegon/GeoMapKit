/// In a style file a zoom-dependent value is either one value (the same at every zoom) or a list of
/// `[zoom, value]` pairs, for example `[[12, 1.5], [16, 3]]`.
extension ZoomValue: Codable where Value: Codable {
    public init(from decoder: Decoder) throws {
        guard var list = try? decoder.unkeyedContainer() else {
            self.init(constant: try decoder.singleValueContainer().decode(Value.self))
            return
        }
        var stops: [Stop] = []
        while !list.isAtEnd {
            var pair = try list.nestedUnkeyedContainer()
            let zoom = try pair.decode(Double.self)
            guard zoom.isFinite else {
                throw DecodingError.dataCorruptedError(in: pair, debugDescription: "a stop's zoom must be a finite number")
            }
            let value = try pair.decode(Value.self)
            guard pair.isAtEnd else {
                throw DecodingError.dataCorruptedError(in: pair, debugDescription: "a stop is [zoom, value] and has exactly two items")
            }
            stops.append(Stop(zoom: zoom, value: value))
        }
        guard let value = ZoomValue(stops: stops) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "needs at least one [zoom, value] stop"))
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        if stops.count == 1, stops[0].zoom == 0 {
            try stops[0].value.encode(to: encoder)
            return
        }
        var list = encoder.unkeyedContainer()
        for stop in stops {
            var pair = list.nestedUnkeyedContainer()
            try pair.encode(stop.zoom)
            try pair.encode(stop.value)
        }
    }
}
