/// How the subclass byte of a feature is laid out.
///
/// The low six bits hold the specific value of the class (for example the
/// `highway` value). Bit 6 marks a bridge and bit 7 a tunnel, so lower bands, which
/// carry no tags, can still draw casings and dashes.
public enum SubclassBits {
    /// The bridge bit.
    public static let bridge: UInt8 = 0x40
    /// The tunnel bit.
    public static let tunnel: UInt8 = 0x80
    /// The mask of the specific value.
    public static let valueMask: UInt8 = 0x3f

    /// The specific value of a subclass byte, without the bridge and tunnel bits.
    public static func value(of subclass: UInt8) -> UInt8 { subclass & valueMask }

    /// Whether the subclass byte marks a bridge.
    public static func isBridge(_ subclass: UInt8) -> Bool { subclass & bridge != 0 }

    /// Whether the subclass byte marks a tunnel.
    public static func isTunnel(_ subclass: UInt8) -> Bool { subclass & tunnel != 0 }
}
