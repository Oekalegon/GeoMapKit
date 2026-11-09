import Foundation

/// How much smaller the name of a smaller place is written than the name of the largest place in view.
///
/// The largest place on the map keeps the font size of the style. A place with a tenth of its population is written smaller by one
/// `decades`th of the way down to ``smallest``, and a place `decades` powers of ten smaller (or less) is written at ``smallest``, with
/// the logarithm of the population in between. So the sizes follow the places on the screen: in a view of Utrecht Houten is smaller,
/// in a view of a Norwegian valley a town of 8,000 is the largest and gets the full size. ``strength`` says how much of this applies at a
/// zoom: 1 all of it, 0 none, so that zoomed in all places have the size of the style.
///
/// The largest place is taken from the places in view, so the sizes of the other names change a little while panning when the largest
/// place leaves the screen.
public struct PopulationScale: Sendable, Equatable {
    /// The scale of the font size for a place `decades` powers of ten smaller than the largest one, more than 0 and at most 1.
    public var smallest: Double
    /// The number of powers of ten of population over which the scale goes from 1 down to ``smallest``, more than 0.
    public var decades: Double
    /// How much of the scale applies, by zoom: 1 all of it, 0 none.
    public var strength: ZoomValue<Double>

    /// Creates a scale, or `nil` if a number is not valid.
    public init?(smallest: Double, decades: Double, strength: ZoomValue<Double> = ZoomValue(constant: 1)) {
        guard smallest.isFinite, smallest > 0, smallest <= 1, decades.isFinite, decades > 0 else { return nil }
        self.smallest = smallest
        self.decades = decades
        self.strength = strength
    }

    /// The factor for the font size of a place of `population` people when the largest place in view has `largest`, at a zoom.
    public func scale(population: Int, largest: Int, atZoom zoom: Double) -> Double {
        let people = Double(max(population, 1)), top = Double(max(largest, 1))
        let down = max(0, log10(top) - log10(people)) / decades
        let full = 1 - (1 - smallest) * min(down, 1)
        let weight = min(max(strength.value(atZoom: zoom), 0), 1)
        return 1 + (full - 1) * weight
    }
}

extension PopulationScale: Codable {
    private enum Keys: String, CodingKey, CaseIterable { case smallest, decades, strength }

    public init(from decoder: Decoder) throws {
        try decoder.requireKnownKeys(Keys.self)
        let c = try decoder.container(keyedBy: Keys.self)
        let strength = try c.decodeIfPresent(ZoomValue<Double>.self, forKey: .strength) ?? ZoomValue(constant: 1)
        guard let value = PopulationScale(
            smallest: try c.decode(Double.self, forKey: .smallest), decades: try c.decode(Double.self, forKey: .decades), strength: strength)
        else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "expects a smallest scale above 0 and at most 1, and decades above 0"))
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(smallest, forKey: .smallest)
        try c.encode(decades, forKey: .decades)
        if strength != ZoomValue(constant: 1) { try c.encode(strength, forKey: .strength) }
    }
}
