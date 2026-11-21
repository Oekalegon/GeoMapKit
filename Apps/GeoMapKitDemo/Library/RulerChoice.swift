import MapUI

/// What the user chose for the scale ruler of the map. The ruler itself (its distances, when it shows) is the package's
/// (`ScaleRulerSettings` of `MapUI`); this is the choice that is kept between launches.
enum RulerChoice: String, CaseIterable, Identifiable {
    case off = "Off"
    case afterMoving = "While moving"
    case always = "Always"

    /// The key under which the choice is kept.
    static let storageKey = "scaleRuler"

    var id: String { rawValue }

    var settings: ScaleRulerSettings {
        switch self {
        case .off: .hidden
        case .afterMoving: .afterMoving
        case .always: .always
        }
    }
}
