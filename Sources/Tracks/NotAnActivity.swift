import Foundation

/// Why a track is not an activity (see ``ActivityRules``).
public enum NotAnActivity: Error, Equatable, LocalizedError {
    /// There are fewer points with a time than the rules need.
    case tooFewPoints(Int)
    /// Too few of the points have a time. A planned route has none.
    case tooFewTimes(fraction: Double)
    /// The time of the point at this index (in the points that have one) is earlier than the one before by more than the tolerance.
    case timeGoesBack(index: Int, seconds: Double)
    /// The first and the last time are the same.
    case noDuration

    public var errorDescription: String? {
        switch self {
        case .tooFewPoints(let count): "Only \(count) points have a time."
        case .tooFewTimes(let fraction): "Only \(Int((fraction * 100).rounded())) % of the points have a time; a planned route has none."
        case .timeGoesBack(let index, let seconds): "The time goes back by \(Int(seconds.rounded())) s at point \(index)."
        case .noDuration: "The track starts and ends at the same time."
        }
    }
}
