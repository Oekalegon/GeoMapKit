/// How a track is matched to a ``LineNetwork``: how far a fix may be from a line, how much the route between two fixes may differ from
/// the straight step, and which lines count.
///
/// The numbers are for a run on foot. A sport that is fast or uses other lines (a ride on roads, a ski on tracks) chooses its own; the
/// package does not know the sport, so the app does.
public struct MatchingRules: Sendable, Equatable {
    /// The distance from a fix, in metres, within which a line is a candidate for it.
    public var reach: Double
    /// The standard deviation of the error of a fix, in metres. A fix at this distance from a line is a good match; at twice this, a poor
    /// one.
    public var gpsSigma: Double
    /// How much a route that is longer or shorter than the straight step between two fixes costs, in metres: a difference of this much
    /// costs one unit (Newson and Krumm's beta).
    public var transitionBeta: Double
    /// How many times as long as the straight step the route between two fixes may be, and the metres that are added to that for the
    /// error of the fixes.
    public var maximumDetour: Double
    /// See ``maximumDetour``.
    public var detourSlack: Double
    /// The most candidate lines for one fix; the nearest are kept.
    public var maximumCandidates: Int
    /// The distance from a line, in metres, at which a fix is as likely to be on no line as on that line. A fix further out is left raw
    /// when no line suits the route better.
    public var offNetworkDistance: Double
    /// What it costs to leave the network and to come back to it, in the units of ``transitionBeta``. A higher value keeps short
    /// excursions on the lines.
    public var switchPenalty: Double
    /// The shortest distance, in metres, between two fixes that are used; fixes closer than this to the last one used are skipped, so
    /// a track recorded once a second is not matched point by point.
    public var minimumSpacing: Double
    /// The gap, in metres, that is bridged between two dead ends of the network (a way that is cut at a cell border and does not join).
    public var hopDistance: Double
    /// The feature classes that count as lines; by default ``LineNetwork/travelClasses``.
    public var classes: Set<UInt8>

    /// Creates rules; negative values are made 0, and at least one candidate is kept.
    ///
    /// - Parameters:
    ///   - reach: The distance within which a line is a candidate, in metres.
    ///   - gpsSigma: The error of a fix, in metres; at least 1.
    ///   - transitionBeta: The route difference that costs one unit, in metres; at least 1.
    ///   - maximumDetour: How many times the straight step a route may be.
    ///   - detourSlack: Metres added to that.
    ///   - maximumCandidates: The most candidates for one fix.
    ///   - offNetworkDistance: The distance at which a fix is as likely to be off the lines as on them, in metres.
    ///   - switchPenalty: The cost of leaving or rejoining the lines.
    ///   - minimumSpacing: The shortest step between fixes that are used, in metres.
    ///   - hopDistance: The gap between dead ends that is bridged, in metres.
    ///   - classes: The feature classes that count as lines.
    public init(
        reach: Double = 40, gpsSigma: Double = 10, transitionBeta: Double = 10, maximumDetour: Double = 3, detourSlack: Double = 60,
        maximumCandidates: Int = 6, offNetworkDistance: Double = 30, switchPenalty: Double = 4, minimumSpacing: Double = 10,
        hopDistance: Double = 3, classes: Set<UInt8> = LineNetwork.travelClasses
    ) {
        self.reach = max(reach, 0)
        self.gpsSigma = max(gpsSigma, 1)
        self.transitionBeta = max(transitionBeta, 1)
        self.maximumDetour = max(maximumDetour, 1)
        self.detourSlack = max(detourSlack, 0)
        self.maximumCandidates = max(maximumCandidates, 1)
        self.offNetworkDistance = max(offNetworkDistance, 0)
        self.switchPenalty = max(switchPenalty, 0)
        self.minimumSpacing = max(minimumSpacing, 0)
        self.hopDistance = max(hopDistance, 0)
        self.classes = classes
    }

    /// Reach 40 m, an error of 10 m, a route difference of 10 m for one unit, a route of up to 3 times the step and 60 m more, 6
    /// candidates, off the lines at 30 m, a cost of 4 to leave or rejoin, fixes at least 10 m apart, a bridge of 3 m, and all travel
    /// classes.
    public static let standard = MatchingRules()
}
