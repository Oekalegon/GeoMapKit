import FeatureStore
import FeatureStoreBuilder
import Foundation
import GeoCore
import Regions

/// What `build-region` is asked to build.
public struct BlockRequest: Sendable {
    /// The area to cover.
    public enum Area: Sendable, Equatable {
        /// Every block that meets a box.
        case box(BoundingBox)
        /// Every block that meets one of these regions (ids of the region index, for example `sweden`).
        case regions([String])
        /// Exactly these blocks, as tiles of the block zoom, for building a few of them again.
        case tiles([TileID])
    }

    /// The area.
    public var area: Area
    /// The folder for the block files and the manifest.
    public var output: URL
    /// The zoom of the block grid; 8 gives tiles of about 78 km at 60° N.
    public var blockZoom: Int
    /// The most blocks built at once. Each holds its cut in memory: about 0.75 GB for a block of zoom 8.
    public var jobs: Int
    /// The margin around a block that is cut, in degrees, so that objects near its edge are whole.
    public var margin: Double
    /// The copy to build.
    public var profile: BuildProfile
    /// The cache folder of the source files, or `nil` for the default one.
    public var cacheDirectory: URL?
    /// Whether to build the blocks again although they are built from the same source files. This is for a change of the
    /// builder that does not change the rule table (so the other blocks of the set stay valid), when only some blocks gain
    /// from it: run it over the area of those blocks.
    public var rebuild: Bool
    /// Whether the sea of open-sea blocks is added after the build (question 53); `false` leaves the holes, for a comparison.
    public var fillsOpenSea: Bool

    /// The zoom of the block grid when a request does not say.
    public static let defaultBlockZoom = 8
    /// The margin of the cut, in degrees, when a request does not say.
    public static let defaultMargin = 0.1

    /// Creates a request.
    public init(
        area: Area, output: URL, blockZoom: Int = BlockRequest.defaultBlockZoom, jobs: Int = 1, margin: Double = BlockRequest.defaultMargin, profile: BuildProfile = .full,
        cacheDirectory: URL? = nil, rebuild: Bool = false, fillsOpenSea: Bool = true
    ) {
        self.rebuild = rebuild
        self.area = area
        self.output = output
        self.blockZoom = blockZoom
        self.jobs = jobs
        self.margin = margin
        self.profile = profile
        self.cacheDirectory = cacheDirectory
        self.fillsOpenSea = fillsOpenSea
    }
}

/// What happened to one block.
public struct BlockOutcome: Sendable, Equatable {
    /// How the block ended.
    public enum Status: Sendable, Equatable {
        /// The block was cut and built.
        case built(bytes: Int64, cells: Int, seconds: Double)
        /// The block was already built from the same source files, so it was left as it is.
        case upToDate
        /// No source file covers the block, or the cut has no cell to store.
        case empty
    }

    /// The column of the tile at the block zoom.
    public let x: Int
    /// The row of the tile.
    public let y: Int
    /// What happened.
    public let status: Status
    /// The regions whose files the block was built from.
    public let regions: [String]
}

/// The result of a `build-region` run.
public struct BlockRunReport: Sendable {
    /// One outcome per block of the area, in the order of the tiles.
    public let outcomes: [BlockOutcome]
    /// The manifest file.
    public let manifestURL: URL
    /// The total time.
    public let totalTime: Duration
    /// The peak memory footprint of the process in bytes, if known.
    public let peakFootprint: Int64?
    /// Warnings: source files that are older than 30 days and were not checked.
    public let warnings: [String]
    /// What the open-sea pass did, or `nil` if it did not run (the Watch profile has no coastline class to see).
    public let openSea: OpenSea.Report?
}
