/// How a map shows the data credit (the ODbL credit for OpenStreetMap data).
///
/// A style chooses a default: ``MapStyle/standard`` shows the full credit, ``MapStyle/watch`` a short mark, because
/// the full text is wider than most of a Watch screen. The credit still has to be reachable somewhere. With
/// ``hidden`` the app is responsible for showing it, for example in an About or Data screen, using the string
/// that every store file carries (`FeatureStoreFile.attribution`). Images that leave the app, such as exported
/// PNGs, should use ``full``.
///
/// This is a convenience for the layout, not legal advice; check the OpenStreetMap Foundation's attribution
/// guidelines for your distribution.
public enum AttributionDisplay: String, Sendable, Equatable, CaseIterable {
    /// The complete credit from the store file, for example "© OpenStreetMap contributors, ODbL".
    case full
    /// A short mark, "© OSM", for small screens. The full text must then be reachable elsewhere in the app.
    case compact
    /// Nothing is drawn on the map. The app must show the credit itself.
    case hidden

    /// The short mark used by ``compact``.
    public static let compactText = "© OSM"

    /// The text to draw for a store file's credit, or `nil` if nothing should be drawn.
    ///
    /// - Parameter credit: The credit string of the store file. An empty string always gives `nil`.
    public func text(for credit: String) -> String? {
        guard !credit.isEmpty else { return nil }
        switch self {
        case .full: return credit
        case .compact: return Self.compactText
        case .hidden: return nil
        }
    }
}
