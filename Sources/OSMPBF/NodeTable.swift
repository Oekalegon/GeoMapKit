/// A table of node records sorted by ID, searched by binary search.
///
/// Eight-byte IDs in a sorted array use far less memory than a hash set, and
/// files are normally sorted by ID already, so building the table is cheap.
struct NodeTable {
    private(set) var records: [NodeRecord]

    /// Creates a table, sorting the records by ID.
    init(sorting records: consuming [NodeRecord]) {
        // `consuming` lets the caller hand the array over, so sorting happens in place
        // instead of on a second copy of what can be a hundred megabytes.
        records.sort { $0.id < $1.id }
        self.records = records
    }

    /// Hands over the records and leaves the table empty, so the caller holds the only reference.
    mutating func takeRecords() -> [NodeRecord] {
        defer { records = [] }
        return records
    }

    /// The index of the record with the given ID, or `nil`.
    func index(of id: Int64) -> Int? {
        var low = 0
        var high = records.count
        while low < high {
            let middle = low + (high - low) / 2
            if records[middle].id < id { low = middle + 1 } else { high = middle }
        }
        return low < records.count && records[low].id == id ? low : nil
    }

    /// The first ID that appears more than once, or `nil` if all IDs are unique.
    var firstDuplicateID: Int64? {
        for index in records.indices.dropFirst() where records[index].id == records[index - 1].id {
            return records[index].id
        }
        return nil
    }

    func contains(_ id: Int64) -> Bool {
        index(of: id) != nil
    }
}
