/// How many labels a map shows and how closely they may sit together.
///
/// These settings apply to all classes at once, on top of each class's own ``LabelStyle``. Fewer, sparser labels
/// suit a small screen: the Watch style uses a larger ``padding`` and a ``maximumCount``.
public struct LabelSettings: Sendable, Equatable {
    /// The clear space kept around every label, in points. Two labels end up about twice this far apart.
    /// Larger values give fewer labels. Never negative.
    public var padding: Double
    /// The most labels placed in one view, or `nil` for no limit. Labels are placed in priority order, so the
    /// highest priority labels are the ones that stay.
    public var maximumCount: Int?

    /// The padding used when a style does not say otherwise.
    public static let defaultPadding = 2.0

    /// Creates label settings. A negative or non-finite padding becomes 0 and a negative count becomes 0.
    public init(padding: Double = LabelSettings.defaultPadding, maximumCount: Int? = nil) {
        self.padding = padding.isFinite ? max(padding, 0) : 0
        self.maximumCount = maximumCount.map { max($0, 0) }
    }
}
