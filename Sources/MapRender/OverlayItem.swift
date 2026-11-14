/// One thing an overlay has to draw for a viewport, in screen points.
public enum OverlayItem: Sendable, Equatable {
    case line(OverlayLine)
    case polygon(OverlayPolygon)
    case marker(OverlayMarker)
}
