import Foundation

extension StoreManifest {
    /// One coarse level of the map (question 50): the same features as the blocks, simplified for a range of zooms and cut into
    /// larger cells, so that a view of hundreds of kilometres touches a few thousand cells.
    ///
    /// A level with the top zoom *t* serves the zooms above *t* − 1 up to *t*. Its cells have the storage zoom *t* + 2, its files
    /// hold the overview band only, and its blocks are tiles of ``blockZoom``.
    public struct Level: Codable, Equatable, Sendable {
        /// The top zooms a level can have.
        public static let topZooms = 1...10

        /// The highest zoom the level serves.
        public var topZoom: Int
        /// The zoom of the cells, `topZoom + 2`.
        public var storageZoom: Int
        /// The zoom of the tiles that make the blocks of the level, at most the storage zoom and the block zoom of the base blocks.
        public var blockZoom: Int
        /// The raw values of the feature classes the level holds.
        public var classes: [Int]
        /// The blocks of the level.
        public var blocks: [LevelBlock]

        /// Creates a level; the storage zoom is `topZoom + 2`.
        public init(topZoom: Int, blockZoom: Int, classes: [Int], blocks: [LevelBlock] = []) {
            self.topZoom = topZoom
            storageZoom = topZoom + 2
            self.blockZoom = blockZoom
            self.classes = classes
            self.blocks = blocks
        }
    }

    /// A block file of a level, and the blocks it was derived from.
    public struct LevelBlock: Codable, Equatable, Sendable {
        /// The block of the base map that a level block was made from: its tile and its size when it was read.
        public struct Origin: Codable, Equatable, Sendable, Hashable {
            /// The column of the tile at the block zoom of the base blocks.
            public var x: Int
            /// The row of the tile at the block zoom of the base blocks.
            public var y: Int
            /// The size of the block file, in bytes.
            public var bytes: Int64

            /// Creates an origin.
            public init(x: Int, y: Int, bytes: Int64) {
                self.x = x
                self.y = y
                self.bytes = bytes
            }
        }

        /// The column of the tile at the block zoom of the level.
        public var x: Int
        /// The row of the tile at the block zoom of the level.
        public var y: Int
        /// The file, relative to the folder of the manifest.
        public var file: String
        /// The size of the file in bytes.
        public var bytes: Int64
        /// When the block was built.
        public var builtAt: Date
        /// The base blocks it was derived from (the blocks of the area it read, margin included), sorted by row and column. A level
        /// block is out of date when these are not the base blocks any more.
        public var derivedFrom: [Origin]

        /// Creates a level block.
        public init(x: Int, y: Int, file: String, bytes: Int64, builtAt: Date, derivedFrom: [Origin]) {
            self.x = x
            self.y = y
            self.file = file
            self.bytes = bytes
            self.builtAt = builtAt
            self.derivedFrom = derivedFrom
        }
    }

    /// A block of a level that is out of date: a block of the base map it was derived from has another size now, or is gone.
    public struct StaleLevelBlock: Equatable, Sendable {
        /// The top zoom of the level.
        public let topZoom: Int
        /// The column of the tile.
        public let x: Int
        /// The row of the tile.
        public let y: Int
    }

    /// The level blocks whose base blocks are not the ones they were derived from any more.
    ///
    /// It compares the sizes of the blocks that each level block lists in `derivedFrom` with the blocks of this manifest. A base block
    /// that is new in the area a level block reads is not seen here (the level block does not list it); `build-levels` finds that, and
    /// `build-region` removes the levels when it rebuilds a block.
    ///
    /// - Returns: The out-of-date level blocks, finest level first.
    public func staleLevelBlocks() -> [StaleLevelBlock] {
        let sizes = Dictionary(uniqueKeysWithValues: blocks.map { ("\($0.x)/\($0.y)", $0.bytes) })
        var result: [StaleLevelBlock] = []
        for level in levels.sorted(by: { $0.topZoom > $1.topZoom }) {
            for block in level.blocks where block.derivedFrom.contains(where: { sizes["\($0.x)/\($0.y)"] != $0.bytes }) {
                result.append(StaleLevelBlock(topZoom: level.topZoom, x: block.x, y: block.y))
            }
        }
        return result
    }

    /// Checks the levels: unique top zooms, the zooms and classes of each, blocks inside the grid, files that stay in the folder and
    /// are not used twice (also not by a base block), and origins inside the grid of the base blocks.
    func validateLevels(usedFiles: inout Set<String>) throws {
        var topZooms = Set<Int>()
        let baseSide = 1 << blockZoom
        for level in levels {
            guard Level.topZooms.contains(level.topZoom), topZooms.insert(level.topZoom).inserted else {
                throw StoreSetError.invalidManifest("the level with the top zoom \(level.topZoom) is out of range or listed twice")
            }
            guard level.storageZoom == level.topZoom + 2, level.storageZoom < storageZoom,
                (0...min(level.storageZoom, blockZoom)).contains(level.blockZoom)
            else {
                throw StoreSetError.invalidManifest(
                    "the level \(level.topZoom) has the storage zoom \(level.storageZoom) and the block zoom \(level.blockZoom): the storage zoom must be \(level.topZoom + 2) and below \(storageZoom), the block zoom from 0 to the smaller of the storage zoom and \(blockZoom)")
            }
            guard level.classes.allSatisfy({ (0...255).contains($0) }), Set(level.classes).count == level.classes.count else {
                throw StoreSetError.invalidManifest("the classes of level \(level.topZoom) are out of range or listed twice")
            }
            let side = 1 << level.blockZoom
            var seen = Set<Int>()
            for block in level.blocks {
                guard (0..<side).contains(block.x), (0..<side).contains(block.y), seen.insert(block.y * side + block.x).inserted else {
                    throw StoreSetError.invalidManifest("the block \(block.x)/\(block.y) of level \(level.topZoom) is outside the grid or listed twice")
                }
                guard block.bytes >= 0, Self.isInsideFolder(block.file), usedFiles.insert(block.file).inserted else {
                    throw StoreSetError.invalidManifest("the file '\(block.file)' of level \(level.topZoom) has a negative size, is not inside the folder or is used twice")
                }
                for origin in block.derivedFrom {
                    guard (0..<baseSide).contains(origin.x), (0..<baseSide).contains(origin.y), origin.bytes >= 0 else {
                        throw StoreSetError.invalidManifest("the block \(block.x)/\(block.y) of level \(level.topZoom) comes from a block outside the grid")
                    }
                }
            }
        }
    }
}
