extension ClassStyle {
    /// The structure a line of this class is drawn as: its own if the class has a style for it, else on the ground.
    ///
    /// - Parameter structure: What the line's subclass byte says.
    public func drawnStructure(for structure: Structure) -> Structure {
        switch structure {
        case .ground: .ground
        case .bridge: bridge != nil ? .bridge : .ground
        case .tunnel: tunnel != nil ? .tunnel : .ground
        }
    }

    /// The stroke to draw lines of a structure with.
    ///
    /// A bridge has the bridge casing instead of the class's casing. A tunnel has no casing, a lower opacity, and its own
    /// dash pattern if the style gives one. Both have flat ends (``LineCap/butt``), whatever the class uses: a bridge's casing
    /// then thickens only the two sides of the deck, not its ends, and a road leaves a tunnel with a clean cut instead of a
    /// round cap.
    ///
    /// - Parameter structure: A drawn structure, see ``drawnStructure(for:)``.
    /// - Returns: The stroke, or `nil` if the class has none.
    public func stroke(for structure: Structure) -> StrokeStyle? {
        guard var stroke else { return nil }
        switch structure {
        case .ground:
            break
        case .bridge:
            if let bridge {
                stroke.casing = bridge.casing
                stroke.cap = .butt
            }
        case .tunnel:
            if let tunnel {
                stroke.casing = nil
                stroke.color = ZoomValue(
                    stops: stroke.color.stops.map { .init(zoom: $0.zoom, value: $0.value.withAlpha($0.value.alpha * tunnel.opacity)) })
                    ?? stroke.color
                if !tunnel.dash.isEmpty { stroke.dash = tunnel.dash }
                stroke.cap = .butt
            }
        }
        return stroke
    }
}
