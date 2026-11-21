import Foundation

/// The units a scale ruler shows.
public enum ScaleRulerUnits: Sendable, Equatable, CaseIterable {
    /// Metres and kilometres.
    case metric
    /// Feet and miles.
    case imperial

    /// The units of a locale: imperial for the US and UK systems, metric otherwise.
    ///
    /// - Parameter locale: The locale; the one of the user by default.
    public static func preferred(for locale: Locale = .current) -> ScaleRulerUnits {
        locale.measurementSystem == .metric ? .metric : .imperial
    }
}
