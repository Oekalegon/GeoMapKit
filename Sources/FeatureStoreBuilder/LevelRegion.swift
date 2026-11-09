/// A rectangle of cells of one zoom.
struct LevelRegion {
    let columns: ClosedRange<Int>
    let rows: ClosedRange<Int>

    func contains(x: Int, y: Int) -> Bool { columns.contains(x) && rows.contains(y) }
}
