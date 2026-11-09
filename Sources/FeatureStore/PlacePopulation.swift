/// Reads the `population` tag of a place, which the renderer uses to thin and to size the names of places.
public enum PlacePopulation {
    /// The number in a `population` tag: its digits, so `12 345`, `12,345` and `12.345` are 12345; `nil` if there are none.
    public static func population(_ value: String?) -> Int? {
        guard let value else { return nil }
        let digits = value.filter { $0.isASCII && $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }
}
