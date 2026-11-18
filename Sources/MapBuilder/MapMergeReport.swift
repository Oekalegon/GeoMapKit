import Foundation

/// What a merge of maps did.
public struct MapMergeReport: Sendable, Equatable {
    /// A tile that more than one map had a block for: one block was kept.
    public struct Overlap: Sendable, Equatable {
        /// The column of the tile at the block zoom.
        public let x: Int
        /// The row of the tile at the block zoom.
        public let y: Int
        /// The name of the folder of the map whose block was kept.
        public let kept: String
        /// The size of the block that was kept, in bytes.
        public let keptBytes: Int64
        /// The names of the folders of the maps whose blocks were left out.
        public let dropped: [String]
        /// The sizes of the blocks that were left out, in bytes, in the order of ``dropped``.
        public let droppedBytes: [Int64]
    }

    /// The blocks of the merged map.
    public let blocks: Int
    /// The blocks that were written to the output: all of them for a new map, the blocks of the other maps for one that is added to.
    public let written: Int
    /// The blocks of the output that another map's larger block replaced (only when adding to a map).
    public let replaced: Int
    /// The tiles that more than one map had a block for.
    public let overlaps: [Overlap]
    /// Whether the merged map has levels (an added-to map keeps its own; a new one has none).
    public let hasLevels: Bool
    /// Things the user should know about the result, such as tiles that more than one map had.
    public let warnings: [String]
    /// What to run next on the merged map (the sea, the levels).
    public let nextSteps: [String]
}
