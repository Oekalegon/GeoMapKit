import FeatureStore

/// Whether a line runs on the ground, over it (a bridge) or under it (a tunnel).
///
/// The builder stores this in two bits of every line's subclass byte (`SubclassBits`), in every band, so even the
/// lower bands, which carry no tags, can draw bridges and tunnels.
public enum Structure: Sendable, Equatable, Hashable {
    /// On the ground, the normal case.
    case ground
    /// Over something else: drawn after (above) the lines on the ground, with a casing.
    case bridge
    /// Under something else: drawn before (below) the lines on the ground, fainter.
    case tunnel

    /// The structure a subclass byte marks. A tunnel wins if both bits are set.
    public init(subclass: UInt8) {
        if SubclassBits.isTunnel(subclass) {
            self = .tunnel
        } else if SubclassBits.isBridge(subclass) {
            self = .bridge
        } else {
            self = .ground
        }
    }
}
