extension ActivityTrack {
    /// The track cut where it jumped or stopped and went on elsewhere, with the places where the runner stood still merged (see
    /// ``TrackCleaner``).
    ///
    /// - Parameter rules: What counts as a break, a jump and a stop.
    public func cleaned(rules: TrackCleaningRules = .standard) -> CleanedTrack {
        TrackCleaner.clean(points, rules: rules)
    }
}
