import Foundation

/// How much smaller the name of a smaller place is written than the name of a big one.
///
/// The stops say the scale of the font size for a population (between two stops the scale follows the logarithm of the population,
/// outside them it is the first or the last scale). ``strength`` says how much of that applies at a zoom: 1 all of it, 0 none, so
/// that at low zoom a small town is written smaller than a city, and zoomed in all places have the size of the style.
public struct PopulationScale: Sendable, Equatable {
    /// One population and the font scale for it.
    public struct Stop: Sendable, Equatable {
        /// The number of people, at least 1.
        public var population: Double
        /// The factor for the font size, more than 0.
        public var scale: Double

        /// Creates a stop.
        public init(population: Double, scale: Double) {
            self.population = population
            self.scale = scale
        }
    }

    /// The stops, sorted by ascending population. Never empty.
    public let stops: [Stop]
    /// How much of the scale applies, by zoom: 1 all of it, 0 none.
    public var strength: ZoomValue<Double>

    /// Creates a scale from stops in any order, or `nil` if the list is empty or a stop is not valid.
    public init?(stops all: [Stop], strength: ZoomValue<Double> = ZoomValue(constant: 1)) {
        guard !all.isEmpty, all.allSatisfy({ $0.population.isFinite && $0.population >= 1 && $0.scale.isFinite && $0.scale > 0 }) else {
            return nil
        }
        stops = all.sorted { $0.population < $1.population }
        self.strength = strength
    }

    /// The factor for the font size of a place of `population` people at a zoom.
    public func scale(population: Int, atZoom zoom: Double) -> Double {
        let people = Double(max(population, 1))
        var full = stops[stops.count - 1].scale
        if people <= stops[0].population {
            full = stops[0].scale
        } else if people < stops[stops.count - 1].population {
            var index = 1
            while stops[index].population < people { index += 1 }
            let a = stops[index - 1], b = stops[index]
            let fraction = (log10(people) - log10(a.population)) / (log10(b.population) - log10(a.population))
            full = a.scale + (b.scale - a.scale) * fraction
        }
        let weight = min(max(strength.value(atZoom: zoom), 0), 1)
        return 1 + (full - 1) * weight
    }
}

extension PopulationScale: Codable {
    private enum Keys: String, CodingKey, CaseIterable { case stops, strength }

    public init(from decoder: Decoder) throws {
        try decoder.requireKnownKeys(Keys.self)
        let c = try decoder.container(keyedBy: Keys.self)
        let pairs = try c.decode([[Double]].self, forKey: .stops)
        guard pairs.allSatisfy({ $0.count == 2 }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .stops, in: c, debugDescription: "expects [population, scale] pairs, for example [[2000, 0.7], [300000, 1]]")
        }
        let strength = try c.decodeIfPresent(ZoomValue<Double>.self, forKey: .strength) ?? ZoomValue(constant: 1)
        guard let value = PopulationScale(stops: pairs.map { Stop(population: $0[0], scale: $0[1]) }, strength: strength) else {
            throw DecodingError.dataCorruptedError(
                forKey: .stops, in: c, debugDescription: "needs at least one pair, with a population of 1 or more and a scale above 0")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(stops.map { [$0.population, $0.scale] }, forKey: .stops)
        if strength != ZoomValue(constant: 1) { try c.encode(strength, forKey: .strength) }
    }
}
