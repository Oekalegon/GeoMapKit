/// In a style file a colour is a string `"#RRGGBB"` or `"#RRGGBBAA"`. Components are stored as 8 bits, so a colour
/// that was not made from 8-bit values is rounded when written.
extension MapColor: Codable {
    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        let digits = text.dropFirst()
        guard text.first == "#", digits.count == 6 || digits.count == 8, let value = UInt32(digits, radix: 16) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "'\(text)' is not a colour; use \"#RRGGBB\" or \"#RRGGBBAA\""))
        }
        if digits.count == 6 {
            self.init(hex: value)
        } else {
            self.init(hex: value >> 8, alpha: Double(value & 0xFF) / 255)
        }
    }

    public func encode(to encoder: Encoder) throws {
        func byte(_ component: Double) -> UInt32 { UInt32((component * 255).rounded()) }
        let alpha = byte(alpha)
        var value = (byte(red) << 16) | (byte(green) << 8) | byte(blue)
        var width = 6
        if alpha != 255 {
            value = (value << 8) | alpha
            width = 8
        }
        let hex = String(value, radix: 16, uppercase: true)
        var container = encoder.singleValueContainer()
        try container.encode("#" + String(repeating: "0", count: width - hex.count) + hex)
    }
}
