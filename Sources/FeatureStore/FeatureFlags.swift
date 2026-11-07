/// Per-piece flags of a stored feature.
public struct FeatureFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    /// The original line or ring continues in the neighbouring cell before this piece.
    public static let continuesBefore = FeatureFlags(rawValue: 1)
    /// The original line or ring continues in the neighbouring cell after this piece.
    public static let continuesAfter = FeatureFlags(rawValue: 2)
    /// The area could not be assembled completely; draw its outline only, never fill it.
    public static let incomplete = FeatureFlags(rawValue: 4)

    static let all: FeatureFlags = [.continuesBefore, .continuesAfter, .incomplete]
}
