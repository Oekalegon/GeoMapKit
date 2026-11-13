import Foundation
import MapBuilder

/// What the status bar says about a run: a title, how far it is and a short detail (question 63, step 3d). The text is made here, not in the
/// view, so that it can be tested.
struct BuildStatusSummary: Equatable {
    /// The stage in words: "Downloading", "Building blocks", …
    var title: String
    /// How far the stage is, from 0 to 1, or `nil` when it cannot be told (the bar then turns without end).
    var fraction: Double?
    /// "38 %, about 12 min left", or `nil`.
    var detail: String?
    /// Whether the run has ended (done, cancelled or failed): the bar then shows no progress.
    var hasEnded: Bool

    /// The summary of a run.
    ///
    /// - Parameters:
    ///   - stage: Where the run is.
    ///   - downloadFraction: The part of the files downloaded, or `nil` when no size is known.
    ///   - blocks: The progress of the blocks, once they have begun.
    ///   - levelBlocksDone: The level blocks that are done.
    static func make(stage: MapBuildModel.Stage, downloadFraction: Double?, blocks: BlockProgress?, levelBlocksDone: Int) -> BuildStatusSummary {
        switch stage {
        case .idle:
            return BuildStatusSummary(title: "", fraction: nil, detail: nil, hasEnded: true)
        case .checking:
            return BuildStatusSummary(title: "Checking the files", fraction: nil, detail: nil, hasEnded: false)
        case .downloading:
            return BuildStatusSummary(title: "Downloading", fraction: downloadFraction, detail: downloadFraction.map(percent), hasEnded: false)
        case .buildingBlocks:
            guard let blocks else { return BuildStatusSummary(title: "Building blocks", fraction: nil, detail: nil, hasEnded: false) }
            var detail = percent(blocks.fraction)
            if let remaining = blocks.remaining { detail += ", about \(timeLeft(remaining)) left" }
            return BuildStatusSummary(title: "Building blocks", fraction: blocks.fraction, detail: detail, hasEnded: false)
        case .buildingLevels:
            return BuildStatusSummary(
                title: "Building levels", fraction: nil, detail: levelBlocksDone > 0 ? "\(levelBlocksDone) level blocks" : nil, hasEnded: false)
        case .registering:
            return BuildStatusSummary(title: "Adding to the library", fraction: nil, detail: nil, hasEnded: false)
        case .done(_, let name):
            return BuildStatusSummary(title: "The map \u{201C}\(name)\u{201D} is ready", fraction: 1, detail: nil, hasEnded: true)
        case .cancelled:
            return BuildStatusSummary(title: "Map build cancelled", fraction: nil, detail: "what is built is kept", hasEnded: true)
        case .failed:
            return BuildStatusSummary(title: "Map build failed", fraction: nil, detail: "click for the reason", hasEnded: true)
        }
    }

    /// "38 %", rounded down so that it does not say 100 % before the end.
    static func percent(_ fraction: Double) -> String { "\(Int((min(max(fraction, 0), 1) * 100).rounded(.down))) %" }

    /// "1 hr, 5 min" or "12 min".
    static func timeLeft(_ duration: Duration) -> String {
        Duration.UnitsFormatStyle(allowedUnits: [.hours, .minutes], width: .abbreviated).format(duration)
    }
}
