import MapStyle

/// Draws a ``MapScene`` into a backend-specific target.
///
/// Everything that depends on the data or the style (decoding, band choice, joining, culling, ordering, label
/// placement) happens before this protocol, in the scene and the label placer. A backend only turns steps into
/// drawing calls, so another backend (Metal, SwiftUI `Canvas`) can be added without touching them.
///
/// Backends draw in screen points with the origin at the top-left corner and y growing downwards, the same
/// coordinates as ``ScreenPoint``.
public protocol MapRenderer: Sendable {
    /// What the backend draws into, for example a `CGContext`.
    associatedtype Target

    /// Draws the whole scene: background, every step in order, then the labels.
    ///
    /// - Parameters:
    ///   - scene: The scene to draw.
    ///   - style: The style the scene was built with; it supplies colours, widths and label styles.
    ///   - target: Where to draw. The caller sets up the coordinate system.
    func draw(_ scene: MapScene, style: MapStyle, into target: Target)
}
