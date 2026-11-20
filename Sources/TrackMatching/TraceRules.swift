/// How off-track stretches are put together into traces. The values are first values from the design note, not yet checked on real
/// tracks.
public struct TraceRules: Sendable, Equatable, Codable {
    /// How near a stretch must be to a trace to run along it, in metres.
    public var joinDistance: Double
    /// How long a stretch must run along a trace to join it, in metres; a shorter part near a trace makes a trace of its own.
    public var minimumJoinLength: Double
    /// The distance between the vertices of a trace, in metres. A stretch is put at this spacing before it is compared or added.
    public var spacing: Double

    /// Creates the rules; values that are not finite or are below the least that works (a join distance of 0, a spacing below 1 m) are
    /// raised to it.
    public init(joinDistance: Double = 12, minimumJoinLength: Double = 50, spacing: Double = 5) {
        func value(_ number: Double, minimum: Double) -> Double { number.isFinite ? max(number, minimum) : minimum }
        self.joinDistance = value(joinDistance, minimum: 1)
        self.minimumJoinLength = value(minimumJoinLength, minimum: 0)
        self.spacing = value(spacing, minimum: 1)
    }

    private enum CodingKeys: String, CodingKey { case joinDistance, minimumJoinLength, spacing }

    /// Decodes the rules and raises values that do not work, as ``init(joinDistance:minimumJoinLength:spacing:)`` does.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            joinDistance: try container.decode(Double.self, forKey: .joinDistance),
            minimumJoinLength: try container.decode(Double.self, forKey: .minimumJoinLength),
            spacing: try container.decode(Double.self, forKey: .spacing))
    }

    /// 12 m, 50 m and 5 m.
    public static let standard = TraceRules()
}
