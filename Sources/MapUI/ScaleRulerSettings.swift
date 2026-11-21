import SwiftUI

/// How a map shows its scale ruler: when, in which units, and how wide at most.
///
/// An app sets it for a map with `View.mapScaleRuler(_:)`. The ruler is drawn on iOS, iPadOS and macOS; on watchOS the setting
/// has no effect and nothing is drawn (the Watch map is small and redrawn only on events).
public struct ScaleRulerSettings: Sendable, Equatable {
    /// When the ruler shows.
    public var visibility: ScaleRulerVisibility
    /// The units of the label.
    public var units: ScaleRulerUnits
    /// The longest the bar may be, in points.
    public var maximumWidth: Double

    /// Creates settings.
    ///
    /// - Parameters:
    ///   - visibility: When the ruler shows.
    ///   - units: The units; those of the user's locale by default.
    ///   - maximumWidth: The longest the bar may be, in points; the bar is as long as the nicest distance that fits.
    public init(visibility: ScaleRulerVisibility, units: ScaleRulerUnits = .preferred(), maximumWidth: Double = 120) {
        self.visibility = visibility
        self.units = units
        self.maximumWidth = maximumWidth.isFinite ? max(maximumWidth, 20) : 120
    }

    /// No ruler: what a map does when the app sets nothing.
    public static let hidden = ScaleRulerSettings(visibility: .hidden)
    /// A ruler that is always there.
    public static let always = ScaleRulerSettings(visibility: .always)
    /// A ruler that shows while the map moves and goes away two seconds after.
    public static let afterMoving = ScaleRulerSettings(visibility: .afterMoving())
}

private struct ScaleRulerKey: EnvironmentKey {
    static let defaultValue = ScaleRulerSettings.hidden
}

extension EnvironmentValues {
    /// The scale ruler settings for maps below this view.
    public var mapScaleRuler: ScaleRulerSettings {
        get { self[ScaleRulerKey.self] }
        set { self[ScaleRulerKey.self] = newValue }
    }
}

extension View {
    /// Sets when and how the maps below this view show their scale ruler.
    ///
    /// - Parameter settings: The settings; ``ScaleRulerSettings/hidden`` is what a map does without this.
    public func mapScaleRuler(_ settings: ScaleRulerSettings) -> some View {
        environment(\.mapScaleRuler, settings)
    }
}
