import FeatureStore
import FeatureStoreBuilder
import Foundation
import MapStyle

/// What `build-levels` is asked to do.
public struct LevelRequest: Sendable {
    /// The folder of the blocks: it holds `manifest.json`, and the levels go to `levels/` in it.
    public var directory: URL
    /// The top zooms of the levels to build, 1 to 10 (a level serves the zooms above the top zoom minus one up to the top zoom).
    public var topZooms: [Int]
    /// How many level blocks are built at once.
    public var jobs: Int
    /// The source cells read around a level block.
    public var margin: Int
    /// The style whose visible classes at the top zoom decide what a level holds.
    public var style: MapStyle

    /// Creates a request.
    public init(
        directory: URL, topZooms: [Int] = [9, 8, 7, 6, 5, 4, 3], jobs: Int = 2, margin: Int = LevelBuilder.defaultMargin,
        style: MapStyle = .standard
    ) {
        self.directory = directory
        self.topZooms = topZooms
        self.jobs = jobs
        self.margin = margin
        self.style = style
    }
}

/// What happened to one block of a level.
public struct LevelOutcome: Sendable, Equatable {
    /// The result for the block.
    public enum Status: Sendable, Equatable {
        /// The file was built.
        case built(bytes: Int64, features: Int, seconds: Double)
        /// The file was there and its base blocks are the same.
        case upToDate
        /// The block has nothing to store.
        case empty
    }

    /// The top zoom of the level.
    public let topZoom: Int
    /// The column of the tile.
    public let x: Int
    /// The row of the tile.
    public let y: Int
    /// The result.
    public let status: Status
    /// The area chains of the block that did not close and are drawn as outlines (0 for a block that was left as it is).
    public let openAreaChains: Int

    init(topZoom: Int, x: Int, y: Int, status: Status, openAreaChains: Int = 0) {
        self.topZoom = topZoom
        self.x = x
        self.y = y
        self.status = status
        self.openAreaChains = openAreaChains
    }
}

/// The size of one level after a run.
public struct LevelSummary: Sendable, Equatable {
    /// The top zoom of the level.
    public let topZoom: Int
    /// The zoom of the cells.
    public let storageZoom: Int
    /// The blocks in the manifest.
    public let blocks: Int
    /// The size of their files in bytes.
    public let bytes: Int64
}

/// What a finished `build-levels` run did.
public struct LevelRunReport: Sendable {
    /// One entry for each level block of the run, in the order of the levels and tiles.
    public let outcomes: [LevelOutcome]
    /// The levels as the manifest has them now.
    public let summaries: [LevelSummary]
    /// The manifest that was written.
    public let manifestURL: URL
    /// The time of the run.
    public let totalTime: Duration
    /// The peak memory footprint of the process, if known.
    public let peakFootprint: Int64?
    /// The area chains that did not close, over the level blocks that were built (they are drawn as outlines).
    public let openAreaChains: Int
    /// The ends of area chains that were joined to another chain, over the level blocks that were built.
    public let areaEndsJoined: Int
    /// How many of those were joined along a line of a cell border.
    public let areaEndsJoinedAlongBorder: Int
}
