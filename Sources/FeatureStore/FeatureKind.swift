/// The geometry type of a stored feature.
public enum FeatureKind: UInt8, Sendable {
    /// One point.
    case point = 0
    /// One or more open lines.
    case line = 1
    /// One or more rings; the renderer fills them with the even-odd rule.
    case area = 2
}
