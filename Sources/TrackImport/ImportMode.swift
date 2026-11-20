/// How an activity is put into the store.
public enum ImportMode: Sendable, Equatable {
    /// The track is cleaned and laid on the lines of the map; its legs count, and what is off the lines is kept as off-track lines.
    case matched
    /// The track is not laid on lines (orienteering, where the runner leaves every path). It adds no legs and no counts, so it is left out
    /// of the segment statistics; its cleaned segments are kept whole as off-track lines, which is what a heat map of such runs needs.
    case raw
}
