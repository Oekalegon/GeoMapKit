import MapStyle

/// Editing the stops of a value that changes with the zoom, one change at a time. Each returns a new value; the stops stay sorted by zoom
/// and a stop moved onto another one's zoom replaces it (as `ZoomValue` itself does).
extension ZoomValue {
    /// Whether the value is the same at every zoom.
    var isConstant: Bool { stops.count == 1 }

    /// A value with one more stop, two zooms after the last (at most 24), with the value of the last stop.
    func addingStop() -> ZoomValue {
        let last = stops[stops.count - 1]
        let zoom = min(last.zoom + 2, 24)
        return ZoomValue(stops: stops + [Stop(zoom: zoom, value: last.value)]) ?? self
    }

    /// Without a stop; the last one stays, since a value needs a stop.
    func removingStop(at index: Int) -> ZoomValue {
        guard stops.count > 1, stops.indices.contains(index) else { return self }
        var rest = stops
        rest.remove(at: index)
        return ZoomValue(stops: rest) ?? self
    }

    /// With the zoom of a stop changed to a zoom between 0 and 24.
    func settingZoom(_ zoom: Double, at index: Int) -> ZoomValue {
        guard stops.indices.contains(index), zoom.isFinite else { return self }
        var all = stops
        all[index].zoom = min(max(zoom, 0), 24)
        return ZoomValue(stops: all) ?? self
    }

    /// With the value of a stop changed.
    func settingValue(_ value: Value, at index: Int) -> ZoomValue {
        guard stops.indices.contains(index) else { return self }
        var all = stops
        all[index].value = value
        return ZoomValue(stops: all) ?? self
    }

    /// The same value at every zoom: the first stop's.
    func asConstant() -> ZoomValue { ZoomValue(constant: stops[0].value) }
}
