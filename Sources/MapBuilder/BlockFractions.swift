import Synchronization

/// How far each block that is being built has come, from 0 to 1, for the progress of a run. The blocks are built on several threads and
/// report here; the run reads the sum from its own task.
final class BlockFractions: Sendable {
    private let table = Mutex<[Int: Double]>([:])

    /// Sets the part of a block that is done. It never goes down: a step that is reported again with a smaller part (two passes in a row
    /// can) does not move the bar back.
    func set(_ fraction: Double, forBlock position: Int) {
        table.withLock { $0[position] = max($0[position] ?? 0, min(max(fraction, 0), 1)) }
    }

    /// Takes a block out when it is done: it is counted as finished then.
    func remove(block position: Int) { table.withLock { _ = $0.removeValue(forKey: position) } }

    /// The sum of the parts of the blocks that are being built.
    var sum: Double { table.withLock { $0.values.reduce(0, +) } }
}
