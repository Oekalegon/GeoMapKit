/// The subclass bytes of the `place` class: the rank of a place, which the style uses to hold the smaller ones back at low zoom.
public enum PlaceRank {
    /// `place=city`.
    public static let city: UInt8 = 1
    /// `place=town` with 35,000 people or more, or without a `population` tag.
    public static let town: UInt8 = 2
    /// `place=village`.
    public static let village: UInt8 = 3
    /// `place=town` with a `population` tag below ``smallTownPopulation``. It is stored in the overview band like a town; the style
    /// decides from which zoom it is named.
    public static let smallTown: UInt8 = 13
    /// The number of people below which a town is a small town.
    public static let smallTownPopulation = 35_000
}
