/// A set of 64-bit IDs kept as a sorted array and searched by binary search.
///
/// Eight bytes per ID, against several times that for a hash set.
struct SortedIDs {
    /// The IDs, sorted ascending, without duplicates.
    private(set) var ids: [Int64]

    /// Sorts and de-duplicates a list of IDs, in place (the array is consumed).
    init(unsorted ids: consuming [Int64]) {
        ids.sort()
        var kept = 0
        for index in ids.indices where kept == 0 || ids[kept - 1] != ids[index] {
            ids[kept] = ids[index]
            kept += 1
        }
        ids.removeLast(ids.count - kept)
        self.ids = ids
    }

    /// Wraps IDs that are already sorted ascending and unique.
    init(sortedUnique ids: [Int64]) {
        self.ids = ids
    }

    func contains(_ id: Int64) -> Bool {
        Self.index(of: id, in: ids) != nil
    }

    /// The position of an ID in a sorted array, or `nil`.
    static func index(of id: Int64, in sortedIDs: [Int64]) -> Int? {
        var low = 0
        var high = sortedIDs.count
        while low < high {
            let middle = low + (high - low) / 2
            if sortedIDs[middle] < id { low = middle + 1 } else { high = middle }
        }
        return low < sortedIDs.count && sortedIDs[low] == id ? low : nil
    }
}
