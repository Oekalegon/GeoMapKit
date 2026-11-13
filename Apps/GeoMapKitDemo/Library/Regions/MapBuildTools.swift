import Foundation
import MapBuilder
import Regions

/// The two builds the app runs, as values, so that the tests of `MapBuildModel` need no real build.
///
/// A callback is called from the task that runs the build, not from the main actor; the model hops to the main actor itself.
struct MapBuildTools: Sendable {
    /// Builds the blocks of a request. The catalog is the list of regions that is already loaded, so no index is fetched again.
    var buildBlocks: @Sendable (BlockRequest, any RegionCatalog, @escaping @Sendable (BlockProgress) -> Void) async throws -> BlockRunReport
    /// Builds the levels of a set of blocks; called with each level block when it is done.
    var buildLevels: @Sendable (LevelRequest, @escaping @Sendable (LevelOutcome) -> Void) async throws -> LevelRunReport

    /// The name the app gives itself to the servers it asks.
    static let userAgent = "GeoMapKitDemo"

    /// The real builds of `MapBuilder`.
    static let live = MapBuildTools(
        buildBlocks: { request, catalog, progress in
            try await MapBuilder.buildRegion(request, catalog: catalog, userAgent: userAgent, onProgress: { progress($0) })
        },
        buildLevels: { request, progress in
            try await MapBuilder.buildLevels(request, progress: { progress($0) })
        })
}
