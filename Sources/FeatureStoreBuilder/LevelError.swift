/// Why a level cannot be built.
public enum LevelError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The top zoom of a level is outside 1 to 11.
    case invalidTopZoom(Int)
    /// The block of the level is finer than the cells of the level, or the level is not coarser than the source.
    case invalidTile(String)
    /// The block and its margin hold more source cells than ``LevelBuilder/maximumRegionCells``.
    case regionTooLarge(cells: Int)
    /// The source holds no overview band, which the levels are made from.
    case noOverviewBand

    public var description: String {
        switch self {
        case .invalidTopZoom(let zoom): return "a level needs a top zoom from 1 to 11, not \(zoom)"
        case .invalidTile(let reason): return "the block of the level is not valid: \(reason)"
        case .regionTooLarge(let cells): return "the block and its margin hold \(cells) source cells, more than \(LevelBuilder.maximumRegionCells)"
        case .noOverviewBand: return "the source holds no overview band; the levels are made from it"
        }
    }
}
