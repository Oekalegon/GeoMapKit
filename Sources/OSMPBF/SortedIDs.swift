/// A set of 64-bit IDs kept as a sorted array and searched by binary search.
///
/// Eight bytes per ID, against several times that for a hash set.
struct SortedIDs {
    /// The IDs, sorted ascending, without duplicates.
    private(set) var ids: [Int64]

    /// Sorts and de-duplicates a list of IDs.
    init(unsorted ids: [Int64]) {
        var sorted = ids
        sorted.sort()
        var unique: [Int64] = []
        unique.reserveCapacity(sorted.count)
        for id in sorted where unique.last != id { unique.append(id) }
        self.ids = unique
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
