import Foundation
import MapBuilder

/// The steps of a merge of maps as values, so that the tests of `MapMergeModel` need no real maps (the same idea as `MapBuildTools`).
///
/// A callback is called from the task that runs the step, not from the main actor.
struct MapMergeTools: Sendable {
    /// Puts the blocks of the maps in one map; called with the blocks written and the blocks to write.
    var merge: @Sendable (MapMergeRequest, @escaping @Sendable (Int, Int) -> Void) async throws -> MapMergeReport
    /// Gives the blocks of the merged map that no source outline touches their sea; returns the number of blocks it wrote or extended.
    var fillSea: @Sendable (URL) async throws -> Int
    /// Builds the levels of the merged map; called with the state of the run when a level block starts or is done.
    var buildLevels: @Sendable (LevelRequest, @escaping @Sendable (LevelProgress) -> Void) async throws -> LevelRunReport

    /// The real steps of `MapBuilder`. The sea is filled with the region list and the source files of `cacheDirectory`.
    static func live(cacheDirectory: URL) -> MapMergeTools {
        MapMergeTools(
            merge: { request, progress in try await MapBuilder.mergeMaps(request) { progress($0, $1) } },
            fillSea: { folder in
                let report = try await MapBuilder.fillOpenSea(folder: folder, cacheDirectory: cacheDirectory, userAgent: MapBuildTools.userAgent)
                return report.created.count + report.extended.count
            },
            buildLevels: { request, progress in try await MapBuilder.buildLevels(request, onProgress: { progress($0) }) })
    }
}
